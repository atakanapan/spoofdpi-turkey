# Rationale and Empirical Findings

This document provides the empirical justification for the SpoofDPI flag combination employed by `spoofdpi-tr`. The configuration was developed iteratively against a live residential connection on a Turkish ISP; alternatives that were considered and rejected during this process are documented below so that future operators on different ISPs may select among them as needed.

## Adversarial Model

Three filtering mechanisms were observed on the test network:

1. **DNS hijacking.** The customer-premises gateway (`192.168.1.1`) forwards resolution requests to ISP recursive resolvers, which return sinkhole addresses for BTK-restricted domains.
2. **TLS SNI inspection.** TCP RST injection was observed on TLS handshakes whose ClientHello contained an SNI value matching a restricted hostname.
3. **DoH transport blocking.** TLS handshakes to well-known DoH endpoints (`1.1.1.1:443`, `dns.google:443`) failed to complete; the four- to five-second timeout observed for `curl https://1.1.1.1/dns-query` strongly suggests deep-packet-level interference at the application data exchange.

## Per-Argument Justification

### `--auto-configure-network`

Causes SpoofDPI to invoke `networksetup` and configure the macOS system-wide HTTP/HTTPS proxy at startup, reverting the configuration on termination. This invocation requires administrator privileges; without `sudo`, the flag is a silent no-op and no proxy is applied. The `spoofdpi-tr` wrapper therefore re-executes itself under `sudo` when not already privileged.

### `--dns-mode udp` and `--dns-addr 1.1.1.1:53`

The initial hypothesis — that DNS-over-HTTPS (`--dns-mode https`) would circumvent ISP-level DNS hijacking — was empirically disproven. TLS handshakes to `https://1.1.1.1/dns-query` and `https://dns.google/dns-query` consistently failed to complete within the 5-second timeout window:

```text
HTTP 000 time=4.012s   (https://1.1.1.1/dns-query)
HTTP 000 time=5.005s   (https://dns.google/dns-query)
```

Direct UDP resolution against the same operators, however, returned consistent, unrejected responses. The following illustration uses `example.com` as a placeholder hostname; equivalent behavior was observed across the actual targets of interest:

```sh
$ dig @1.1.1.1 +short example.com
$ dig @8.8.8.8 +short example.com
$ dig @9.9.9.9 +short example.com
```

All three public resolvers returned identical address records, consistent with the authoritative response and incompatible with the sinkhole behavior observed via the ISP's own resolver.

The configuration therefore routes UDP DNS queries directly to `1.1.1.1`, bypassing the customer-premises gateway and, consequently, ISP recursive resolvers — without depending on DoH transport reachability.

### `--https-split-mode random`

The initial hypothesis — that SNI-aware fragmentation (`--https-split-mode sni`) would circumvent SNI inspection for all targets — was empirically disproven for at least one test target (a major real-time messaging platform). The following sweep was conducted across three representative hostnames (anonymized as `Target A`, `Target B`, `Target C`) with HTTP response codes recorded for each combination:

| split-mode | chunk-size | Target A | Target B | Target C |
| --- | --- | --- | --- | --- |
| `sni` | 1 | 200 | **000** | 200 |
| `sni` | 4 | 200 | **000** | 200 |
| `sni` | 8 | 200 | **000** | 200 |
| `random` | 1 | 200 | 200 | 200 |
| `random` | 4 | 200 | 200 | 200 |
| `random` | 8 | 200 | 200 | 200 |
| `chunk` | 1 | 200 | 200 | 200 |
| `chunk` | 4 | 200 | 200 | 200 |
| `chunk` | 8 | 200 | **000** | 200 |

`random` was the only mode that succeeded across the full chunk-size range. Within roughly 60 ms, every `sni`-mode request to `Target B` received HTTP 000, consistent with TCP RST injection observed during the connection-establishment phase. We interpret this as evidence that the observed DPI implementation can re-assemble ClientHello fragments split along the SNI boundary; randomized split points defeat this re-assembly.

### `--dns-cache`

A pure performance optimization. Avoids a UDP round-trip on every request once a domain has been resolved. No security or evasion implication.

## Configurations Considered and Rejected

### TOML configuration file

Initial implementations placed all parameters in `~/.config/spoofdpi/spoofdpi.toml` with the intention of producing a more readable configuration surface. SpoofDPI v1.5.1 emits a `loaded config file` log entry upon parsing this file but **silently ignores its contents**: subsequent log output reflects the compiled-in defaults regardless of file contents.

```text
[app] loaded config file; dir=/Users/.../.config/spoofdpi/spoofdpi.toml
[app]  split; chunk-size=35 disorder=false split-mode=sni
[app]  fake; count=0
```

The TOML key schema is not documented in the binary's `--help` output, and the project's documentation site (`spoofdpi.xvzc.dev`) returned HTTP 404 at the time of testing. All configuration was therefore moved to command-line flags, which are honored as expected.

### `--dns-mode doh` (incorrect value)

The `--help` output documents the permitted values as `<'udp'|'doh'|'sys'>`. At runtime, however, SpoofDPI rejects `doh` as invalid:

```text
invalid value "doh" for flag -dns-mode: value 'doh' is invalid (allowed: udp, https, system)
```

The correct value is `https`. The help text is misleading. This was tested and rejected for the independent reason discussed under DoH transport blocking, above.

### `--https-fake-count` and `--https-disorder`

These flags inject fake ClientHello packets ahead of the real one and transmit fragments out of order, respectively. Both require `pcap` raw-socket access and fail on macOS even when invoked under `sudo`:

```text
create server: failed to resolve gateway MAC: open pcap handle on en0: Permission Denied
```

Granting these permissions on macOS requires either a system entitlement or running as `root` with appropriate `pcap` library configuration. Because randomized splitting alone proved sufficient for all tested targets, these flags were omitted from the default configuration. Operators on more aggressive networks may revisit them; see [Fallback Configurations](#fallback-configurations) below.

## Fallback Configurations

If `spoofdpi-tr` fails to reach a particular target, the following alternatives may be attempted in order of increasing aggressiveness.

### 1. Alternative fragmentation strategy

```sh
sudo /opt/homebrew/bin/spoofdpi \
  --auto-configure-network \
  --dns-mode udp --dns-addr 1.1.1.1:53 --dns-cache \
  --https-split-mode chunk --https-chunk-size 4
```

### 2. Fake packets with low TTL (requires `pcap` access)

```sh
sudo /opt/homebrew/bin/spoofdpi \
  --auto-configure-network \
  --dns-mode udp --dns-addr 1.1.1.1:53 --dns-cache \
  --https-split-mode sni \
  --https-fake-count 1 --default-fake-ttl 8 \
  --https-chunk-size 1 --https-disorder
```

The TTL value should be tuned to the local network topology. Run `traceroute 1.1.1.1` to estimate hop count, then set `--default-fake-ttl` to one or two hops less, so that the decoy packet is dropped after passing the DPI middlebox but before reaching the origin.

### 3. TUN-mode interception (experimental)

```sh
sudo /opt/homebrew/bin/spoofdpi --app-mode tun ...
```

Replaces the HTTP proxy interception model with a TUN virtual interface, capturing all traffic regardless of application proxy support. The SpoofDPI documentation labels this mode experimental.

### 4. Alternative resolver

In the unlikely event that `1.1.1.1` itself is found to be hijacked or rate-limited, substitute resolvers include:

- `--dns-addr 9.9.9.9:53` (Quad9)
- `--dns-addr 8.8.8.8:53` (Google Public DNS)
- `--dns-addr 94.140.14.14:53` (AdGuard DNS)

## Application-Specific Note: the Discord Desktop Updater

The Discord macOS application is, for network purposes, two distinct clients:

1. **The Electron/Chromium front-end** (messages, login, the realtime gateway).
   This honors the macOS *system* proxy that `--auto-configure-network` installs,
   so it is covered by `spoofdpi-tr` with no further action.
2. **The host updater**, a separate binary built on the Rust `reqwest`/`hyper`
   stack. Unlike Chromium, `reqwest` does **not** consult the macOS system proxy;
   it reads only the `HTTPS_PROXY` / `ALL_PROXY` / `HTTP_PROXY` environment
   variables. With `spoofdpi-tr` running but no such variable set, the updater
   connects *directly* to `updates.discord.com`, receives a DPI-injected TLS RST,
   and fails. The failure is recorded in
   `~/Library/Application Support/discord/logs/Discord_updater_rCURRENT.log`:

   ```text
   ERROR [updater_client]: Failed: reqwest::Error { ... host: "updates.discord.com" ...
     source: hyper::Error(Connect, code: -9806, "connection closed via error") }
   ```

   `updates.discord.com` and `discord.com/api/updates` were confirmed to be
   SNI-RST-blocked when reached directly, and to return HTTP 200 when the same
   request is routed through the `random`-split proxy.

**Resolution.** Launch Discord with the proxy environment variables set so the
updater's `reqwest` client routes through SpoofDPI. The `discord-tr` launcher in
this repository does exactly that; equivalently:

```sh
HTTPS_PROXY=http://127.0.0.1:8080 ALL_PROXY=http://127.0.0.1:8080 \
  /Applications/Discord.app/Contents/MacOS/Discord
```

Two details matter. The app must be launched as a direct `exec` of the binary,
**not** via `open` — `open` dispatches through LaunchServices, which does not
propagate the shell environment to the launched process, so the child updater
would not inherit the variables. And SpoofDPI must already be listening on the
referenced port (the default `--listen-addr` is `127.0.0.1:8080`).

Verified 2026-06-25 on Turkcell Superonline: with the variables set, the updater
fetches its manifest successfully (`Already up to date. Nothing to do.`) instead
of looping on the `-9806` connection error.

> Note on `--app-mode tun`: SpoofDPI's experimental TUN mode would, in principle,
> capture the updater's direct connections regardless of proxy awareness. On the
> tested build (v1.5.1, macOS, Apple Silicon) it created the `utun` interface but
> installed neither an IPv4 address nor a default route, so no traffic was
> actually intercepted. The environment-variable approach above is the reliable
> fix on this build.

## Diagnostic Procedure

When investigating a target that fails to connect:

1. **Baseline probe.** Run `curl -v https://<target> 2>&1 | head -30` without the proxy. A "Connection reset" message indicates active RST injection; a "Could not resolve host" indicates DNS hijacking; absence of any response over an extended interval indicates IP-level blocking.
2. **Enable debug logging.** Add `--log-level debug` to the SpoofDPI invocation and inspect the stage at which the connection fails.
3. **Packet capture.** A `tcpdump` capture of the affected handshake can confirm whether a RST originates from a path device (TTL anomalously low or absent IP options) or from the origin.
4. **Report.** Open an issue on this repository with the ISP, the hostnames affected, and the relevant log excerpts.

---

# Türkçe

# Gerekçe ve Ampirik Bulgular

Bu doküman, `spoofdpi-tr` tarafından kullanılan SpoofDPI flag kombinasyonunun ampirik gerekçesini sunmaktadır. Konfigürasyon, bir Türk ISP'sinin ev bağlantısı üzerinde iteratif olarak geliştirilmiştir; süreç boyunca değerlendirilip elenen alternatifler de farklı ISP'lerdeki operatörlerin değerlendirebilmesi için aşağıda belgelenmiştir.

## Threat Model

Test ağında üç filtreleme mekanizması gözlemlenmiştir:

1. **DNS hijacking.** CPE (`192.168.1.1`) resolution isteklerini ISP'nin recursive DNS sunucularına forward etmekte; bu sunucular BTK kısıtlı domain'ler için sinkhole adresler döndürmektedir.
2. **TLS SNI inspection.** ClientHello'sunda kısıtlı hostname içeren TLS handshake'lerde TCP RST injection gözlemlenmiştir.
3. **DoH transport blocking.** Bilinen DoH endpoint'lerine (`1.1.1.1:443`, `dns.google:443`) yönelik TLS handshake'ler tamamlanamamıştır; `curl https://1.1.1.1/dns-query` için gözlemlenen dört ila beş saniyelik timeout, application data exchange seviyesinde derin paket müdahalesini güçlü biçimde işaret etmektedir.

## Argümanların Tek Tek Gerekçesi

### `--auto-configure-network`

SpoofDPI'nin başlangıçta `networksetup` çağırarak macOS sistem genelindeki HTTP/HTTPS proxy'sini ayarlamasını ve process sonlandığında bu yapılandırmayı geri almasını sağlar. Bu çağrı admin privilege gerektirir; `sudo` olmadan flag sessizce göz ardı edilir ve hiçbir proxy uygulanmaz. Bu nedenle `spoofdpi-tr` wrapper'ı, privileged çalışmıyorsa kendini `sudo` altında re-exec eder.

### `--dns-mode udp` ve `--dns-addr 1.1.1.1:53`

İlk hipotez — DNS-over-HTTPS (`--dns-mode https`) ile ISP DNS hijacking'inin aşılabileceği — ampirik olarak çürütülmüştür. `https://1.1.1.1/dns-query` ve `https://dns.google/dns-query` adreslerine yapılan TLS handshake'ler 5 saniyelik timeout penceresinde tutarlı şekilde tamamlanamamıştır:

```text
HTTP 000 time=4.012s   (https://1.1.1.1/dns-query)
HTTP 000 time=5.005s   (https://dns.google/dns-query)
```

Aynı operatörlere doğrudan UDP üzerinden yapılan sorgular ise tutarlı, reddedilmeyen yanıtlar üretmiştir. Aşağıdaki örnekte placeholder hostname olarak `example.com` kullanılmıştır; gerçek ilgili hedefler üzerinde de eşdeğer davranış gözlemlenmiştir:

```sh
$ dig @1.1.1.1 +short example.com
$ dig @8.8.8.8 +short example.com
$ dig @9.9.9.9 +short example.com
```

Üç public resolver de aynı address record'ları döndürmüştür; bu, authoritative yanıt ile uyumlu ve ISP'nin kendi resolver'ı üzerinden gözlemlenen sinkhole davranışıyla bağdaşmamaktadır.

Konfigürasyon bu nedenle UDP DNS sorgularını doğrudan `1.1.1.1`'e yönlendirir; CPE'yi ve dolayısıyla ISP recursive resolver'larını devre dışı bırakır — DoH transport reachability'sine bağımlı olmaksızın.

### `--https-split-mode random`

İlk hipotez — SNI-aware fragmentation'ın (`--https-split-mode sni`) tüm hedefler için SNI inspection'ı aşacağı — test hedeflerinden en az biri (yaygın bir gerçek zamanlı mesajlaşma platformu) için ampirik olarak çürütülmüştür. Aşağıdaki tarama, üç temsili hostname (anonimleştirilmiş olarak `Target A`, `Target B`, `Target C`) üzerinde her kombinasyon için HTTP yanıt kodlarını kaydederek gerçekleştirilmiştir:

| split-mode | chunk-size | Target A | Target B | Target C |
| --- | --- | --- | --- | --- |
| `sni` | 1 | 200 | **000** | 200 |
| `sni` | 4 | 200 | **000** | 200 |
| `sni` | 8 | 200 | **000** | 200 |
| `random` | 1 | 200 | 200 | 200 |
| `random` | 4 | 200 | 200 | 200 |
| `random` | 8 | 200 | 200 | 200 |
| `chunk` | 1 | 200 | 200 | 200 |
| `chunk` | 4 | 200 | 200 | 200 |
| `chunk` | 8 | 200 | **000** | 200 |

`random` tüm chunk-size aralığında başarılı olan tek mod olmuştur. `Target B`'ye yapılan her `sni`-mod isteği yaklaşık 60 ms içinde HTTP 000 döndürmüş; bu, bağlantı kurma aşamasında TCP RST injection ile tutarlıdır. Gözlemlenen DPI uygulamasının SNI sınırından bölünen ClientHello fragment'lerini reassemble edebildiği yorumunu yapıyoruz; rastgele split point'ler bu reassembly'i etkisiz kılmaktadır.

### `--dns-cache`

Saf bir performans optimizasyonudur. Bir domain resolve edildikten sonra her istekte UDP round-trip'i önler. Güvenlik veya bypass etkisi yoktur.

## Değerlendirilip Reddedilen Konfigürasyonlar

### TOML konfigürasyon dosyası

İlk uygulamalar tüm parametreleri daha okunaklı bir konfigürasyon yüzeyi sunma niyetiyle `~/.config/spoofdpi/spoofdpi.toml` dosyasına yerleştirmiştir. SpoofDPI v1.5.1, bu dosyayı işlerken `loaded config file` log girdisi üretmekte, ancak **dosyanın içeriğini sessizce göz ardı etmektedir**: sonraki log çıktısı, dosya içeriğinden bağımsız olarak derleme zamanı default'larını yansıtmaktadır.

```text
[app] loaded config file; dir=/Users/.../.config/spoofdpi/spoofdpi.toml
[app]  split; chunk-size=35 disorder=false split-mode=sni
[app]  fake; count=0
```

TOML key schema'sı binary'nin `--help` çıktısında belgelenmemiş ve projenin dokümantasyon sitesi (`spoofdpi.xvzc.dev`), test sırasında HTTP 404 döndürmüştür. Bu nedenle tüm konfigürasyon, beklendiği gibi işlenen command-line flag'lere taşınmıştır.

### `--dns-mode doh` (hatalı değer)

`--help` çıktısı izin verilen değerleri `<'udp'|'doh'|'sys'>` olarak belgelemektedir. Runtime'da ise SpoofDPI `doh` değerini geçersiz olarak reddetmektedir:

```text
invalid value "doh" for flag -dns-mode: value 'doh' is invalid (allowed: udp, https, system)
```

Doğru değer `https`'tir. Help metni yanıltıcıdır. Bu seçenek, yukarıda DoH transport blocking başlığında tartışılan ayrı nedenle test edilmiş ve reddedilmiştir.

### `--https-fake-count` ve `--https-disorder`

Bu flag'ler sırasıyla gerçek ClientHello'dan önce decoy ClientHello paketleri inject eder ve fragment'leri out-of-order iletir. Her ikisi de `pcap` raw-socket erişimi gerektirmekte ve macOS'ta `sudo` altında dahi başarısız olmaktadır:

```text
create server: failed to resolve gateway MAC: open pcap handle on en0: Permission Denied
```

macOS'ta bu izinleri sağlamak ya sistem entitlement'ı ya da uygun `pcap` kütüphane yapılandırmasıyla `root` olarak çalışmayı gerektirir. Random split tek başına tüm test edilen hedefler için yeterli olduğundan, bu flag'ler default konfigürasyondan çıkarılmıştır. Daha agresif ağlardaki operatörler bu flag'lere dönmek isteyebilir; aşağıda [Fallback Konfigürasyonlar](#fallback-konfig%C3%BCrasyonlar) bölümüne bakınız.

## Fallback Konfigürasyonlar

`spoofdpi-tr` belirli bir hedefe ulaşamazsa, aşağıdaki alternatifler artan agresiflik sırasıyla denenebilir.

### 1. Alternatif fragmentation stratejisi

```sh
sudo /opt/homebrew/bin/spoofdpi \
  --auto-configure-network \
  --dns-mode udp --dns-addr 1.1.1.1:53 --dns-cache \
  --https-split-mode chunk --https-chunk-size 4
```

### 2. Düşük TTL'li decoy paketler (`pcap` erişimi gerektirir)

```sh
sudo /opt/homebrew/bin/spoofdpi \
  --auto-configure-network \
  --dns-mode udp --dns-addr 1.1.1.1:53 --dns-cache \
  --https-split-mode sni \
  --https-fake-count 1 --default-fake-ttl 8 \
  --https-chunk-size 1 --https-disorder
```

TTL değeri yerel ağ topolojisine göre ayarlanmalıdır. `traceroute 1.1.1.1` ile hop sayısı tahmin edilir, ardından `--default-fake-ttl` bu değerin bir-iki eksiğine ayarlanır; böylece decoy paket DPI middlebox'ını geçtikten sonra ancak origin'e ulaşmadan drop edilir.

### 3. TUN-mode interception (experimental)

```sh
sudo /opt/homebrew/bin/spoofdpi --app-mode tun ...
```

HTTP proxy interception modelini bir TUN sanal interface'i ile değiştirir; uygulamanın proxy desteğinden bağımsız olarak tüm trafiği yakalar. SpoofDPI dokümantasyonu bu modu experimental olarak işaretlemektedir.

### 4. Alternatif resolver

`1.1.1.1`'in kendisi hijacked ya da rate-limited bulunduğu beklenmedik bir durumda, alternatif resolver'lar:

- `--dns-addr 9.9.9.9:53` (Quad9)
- `--dns-addr 8.8.8.8:53` (Google Public DNS)
- `--dns-addr 94.140.14.14:53` (AdGuard DNS)

## Tanılama Prosedürü

Bağlanamayan bir hedef için inceleme:

1. **Baseline probe.** Proxy kullanmadan `curl -v https://<hedef> 2>&1 | head -30` çalıştırılır. "Connection reset" mesajı aktif RST injection'a; "Could not resolve host" DNS hijacking'e; uzun bir aralıkta hiçbir yanıt olmaması IP düzeyinde engellemeye işaret eder.
2. **Debug logging.** SpoofDPI çağrısına `--log-level debug` eklenir ve bağlantının hangi aşamada başarısız olduğu incelenir.
3. **Packet capture.** Etkilenen handshake'in `tcpdump` capture'ı, RST'in path üzerindeki bir cihazdan (TTL anormal düşük veya IP option yok) mı yoksa origin'den mi geldiğini doğrulayabilir.
4. **Raporlama.** Bu repo üzerinde ISP, etkilenen hostname'ler ve ilgili log alıntılarıyla birlikte bir issue açılır.
