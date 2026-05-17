# spoofdpi-turkey

One-command macOS deployment of SpoofDPI for Turkey. The installer bootstraps Homebrew and SpoofDPI when absent, then installs a wrapper (`spoofdpi-tr`) that invokes SpoofDPI with flags tuned for the DPI and DNS interference patterns observed on Turkish residential ISPs. The system-wide HTTP/HTTPS proxy is enabled on demand and reverted automatically on termination — no persistent system changes.

**Platform:** macOS only (Apple Silicon and Intel). **Validated against:** macOS 15.x (Apple Silicon), SpoofDPI v1.5.1.

## Background

Internet service providers (ISPs) in Turkey deploy multi-layer traffic filtering at the network level. Three mechanisms are most commonly observed:

1. **DNS hijacking.** Resolution of restricted domains — typically those enumerated by the Information and Communication Technologies Authority ("BTK") — is redirected to sinkhole addresses by the ISP's recursive resolvers.
2. **TLS Server Name Indication (SNI) inspection.** Because the SNI extension in the TLS ClientHello is transmitted in plaintext, ISP middleboxes can identify connections to specific hostnames and terminate them via TCP RST injection.
3. **DoH suppression.** Well-known DNS-over-HTTPS endpoints (e.g., `1.1.1.1`, `dns.google`) are blocked at the transport layer; TLS handshakes to these hosts do not complete.

[SpoofDPI](https://github.com/xvzc/SpoofDPI) addresses these vectors through TLS fragmentation, configurable DNS resolution, and proxy-based traffic interception. However, its default configuration is insufficient under the conditions observed on Turkish networks. This repository provides a configuration that has been empirically validated and a thin installer that bootstraps it on a stock macOS system.

## Installation

A single-command installation is supported, including on a previously unconfigured macOS host:

```sh
curl -fsSL https://raw.githubusercontent.com/atakanapan/spoofdpi-turkey/main/install.sh | bash
```

The installer performs the following steps:

1. Detects the absence of Homebrew; if missing, prompts for confirmation and installs it via the official installer
2. Installs SpoofDPI via `brew install spoofdpi`
3. Deploys the `spoofdpi-tr` wrapper script to `/usr/local/bin/`

For non-interactive provisioning (e.g., automation, CI):

```sh
curl -fsSL https://raw.githubusercontent.com/atakanapan/spoofdpi-turkey/main/install.sh | bash -s -- --yes
```

## Usage

```sh
spoofdpi-tr
```

The wrapper requests administrator privileges once per invocation in order to apply a system-wide HTTP/HTTPS proxy via the macOS `networksetup` utility. Upon termination (SIGINT/SIGTERM), the proxy configuration is reverted automatically; no persistent system modification occurs.

## Configuration

The wrapper invokes `spoofdpi` with the following arguments:

| Argument | Value | Purpose |
| --- | --- | --- |
| `--auto-configure-network` | (flag) | Applies and reverts the macOS system proxy automatically |
| `--dns-mode` | `udp` | Uses standard UDP-based DNS resolution |
| `--dns-addr` | `1.1.1.1:53` | Routes DNS queries to Cloudflare, bypassing the ISP recursive resolver |
| `--dns-cache` | (flag) | Caches DNS responses to reduce per-request latency |
| `--https-split-mode` | `random` | Fragments the TLS ClientHello at randomized byte offsets |

An empirical justification for each argument — including alternatives that were tested and rejected — is provided in [docs/rationale.md](docs/rationale.md).

## Scope of Validation

The configuration has been validated against representative targets in the following categories: major social networks, instant-messaging platforms, video streaming services, and hostnames known to be subject to network-level filtering in Turkey. In the latter case, the wrapper successfully bypasses transport-layer filtering; any subsequent application-layer rejection by the origin (e.g., geographic restrictions enforced by the destination service) is an orthogonal concern and falls outside the scope of this repository.

## ISP Caveat

Validation was conducted against a single Turkish residential ISP. Filtering behavior is known to vary across providers, and the configuration may require adjustment elsewhere. If the wrapper fails to circumvent filtering on a different provider, please open an issue describing the symptoms (e.g., the failing connection stage as observed in `spoofdpi --log-level debug`) and the output of `spoofdpi --version`.

## Removal

```sh
sudo rm /usr/local/bin/spoofdpi-tr
brew uninstall spoofdpi   # optional
```

## Credits

This repository is a configuration wrapper. It does **not** redistribute or modify the SpoofDPI source code or binary.

- **SpoofDPI** — [github.com/xvzc/SpoofDPI](https://github.com/xvzc/SpoofDPI), licensed under Apache License 2.0, © Hyeon Kim and contributors. Installed at runtime via Homebrew.

## License

The contents of this repository (wrapper script, installer, documentation) are released under the MIT License. See [LICENSE](LICENSE).

SpoofDPI itself remains under the Apache License 2.0 and is unmodified by this project.

---

# Türkçe

macOS için tek komutla kurulabilen, Türkiye için özelleştirilmiş config içeren SpoofDPI dağıtımı. Installer Homebrew ve SpoofDPI'yi (yoksa) otomatik kurar; ardından SpoofDPI'yi Türk ev internet sağlayıcılarındaki DPI ve DNS müdahale paternlerine göre ayarlanmış flag'lerle çağıran bir wrapper (`spoofdpi-tr`) yerleştirir. Sistem geneli HTTP/HTTPS proxy talep üzerine aktif olur, process sonlandığında otomatik geri alınır — sistemde kalıcı değişiklik olmaz.

**Platform:** sadece macOS (Apple Silicon ve Intel). **Doğrulama ortamı:** macOS 15.x (Apple Silicon), SpoofDPI v1.5.1.

## Arka Plan

Türkiye'deki internet servis sağlayıcıları (ISP), ağ düzeyinde çok katmanlı bir trafik filtreleme uygulamaktadır. En sık gözlemlenen üç mekanizma:

1. **DNS hijacking.** BTK (Bilgi ve İletişim Teknolojileri Kurumu) tarafından kısıtlı listelenen domain'lere yapılan sorgular, ISP'nin recursive DNS sunucuları tarafından sinkhole adreslere yönlendirilmektedir.
2. **TLS Server Name Indication (SNI) inspection.** TLS ClientHello içindeki SNI uzantısı plaintext olarak iletildiği için, ISP middlebox'ları belirli hostname'lere yapılan bağlantıları tespit edip TCP RST injection ile sonlandırabilmektedir.
3. **DoH suppression.** Bilinen DNS-over-HTTPS endpoint'lerine (`1.1.1.1`, `dns.google` vb.) transport katmanında müdahale edilmekte; bu adreslere yönelik TLS handshake tamamlanamamaktadır.

[SpoofDPI](https://github.com/xvzc/SpoofDPI) bu vektörleri TLS fragmentation, yapılandırılabilir DNS resolver ve proxy tabanlı trafik yakalama yoluyla ele almaktadır. Ancak varsayılan konfigürasyonu Türkiye ağ koşullarında yetersiz kalmaktadır. Bu repo, ampirik olarak doğrulanmış bir konfigürasyon ve standart bir macOS sistemini sıfırdan kurulabilir hale getiren bir installer sunmaktadır.

## Kurulum

Daha önce yapılandırılmamış bir macOS sistemde dahi tek komutla kurulum desteklenmektedir:

```sh
curl -fsSL https://raw.githubusercontent.com/atakanapan/spoofdpi-turkey/main/install.sh | bash
```

Installer şu adımları yürütür:

1. Homebrew'ün yokluğunu tespit eder; yoksa kullanıcı onayı ister ve resmi installer aracılığıyla kurar
2. `brew install spoofdpi` ile SpoofDPI'yi kurar
3. `spoofdpi-tr` wrapper script'ini `/usr/local/bin/` dizinine yerleştirir

Non-interactive kurulum için (otomasyon, CI):

```sh
curl -fsSL https://raw.githubusercontent.com/atakanapan/spoofdpi-turkey/main/install.sh | bash -s -- --yes
```

## Kullanım

```sh
spoofdpi-tr
```

Wrapper, macOS `networksetup` aracı üzerinden sistem genelinde bir HTTP/HTTPS proxy uygulamak için her çalıştırmada bir kez yönetici parolası ister. Process sonlandığında (SIGINT/SIGTERM), proxy yapılandırması otomatik olarak geri alınır; sistemde kalıcı bir değişiklik bırakılmaz.

## Konfigürasyon

Wrapper, `spoofdpi`'yi aşağıdaki argümanlarla çağırır:

| Argüman | Değer | Amaç |
| --- | --- | --- |
| `--auto-configure-network` | (flag) | macOS sistem proxy'sini otomatik uygular ve geri alır |
| `--dns-mode` | `udp` | Standart UDP DNS resolver |
| `--dns-addr` | `1.1.1.1:53` | DNS sorgularını Cloudflare'e yönlendirir, ISP DNS sunucusunu devre dışı bırakır |
| `--dns-cache` | (flag) | DNS yanıtlarını cache'ler |
| `--https-split-mode` | `random` | TLS ClientHello'yu rastgele byte offset'lerinde böler |

Her argümanın ampirik gerekçesi — test edilip elenen alternatifler dahil — [docs/rationale.md](docs/rationale.md) dosyasında sunulmaktadır.

## Doğrulama Kapsamı

Konfigürasyon, aşağıdaki kategorilerdeki temsili hedeflere karşı doğrulanmıştır: yaygın sosyal ağlar, anlık mesajlaşma platformları, video streaming servisleri ve Türkiye'de network seviyesinde filtrelemeye tabi olduğu bilinen hostname'ler. Son kategoride wrapper, transport katmanındaki filtreyi başarıyla aşmaktadır; ardından origin tarafından uygulanan application-layer reddi (ör. hedef servisin coğrafi kısıt uygulaması) ayrı bir konu olup bu repo'nun kapsamı dışındadır.

## ISP Notu

Doğrulama, tek bir Türk ev internet sağlayıcısı üzerinde yapılmıştır. Filtreleme davranışı sağlayıcılar arasında farklılık gösterdiği bilinmektedir; konfigürasyon farklı ortamlarda ayarlama gerektirebilir. Wrapper farklı bir sağlayıcıda işe yaramadığı takdirde lütfen bir issue açın: belirtileri (`spoofdpi --log-level debug` ile gözlemlenen başarısız bağlantı aşaması gibi) ve `spoofdpi --version` çıktısını ekleyin.

## Kaldırma

```sh
sudo rm /usr/local/bin/spoofdpi-tr
brew uninstall spoofdpi   # opsiyonel
```

## Atıf

Bu repo bir konfigürasyon wrapper'ıdır. SpoofDPI kaynak kodunu veya binary'sini **redistribute etmez** ve değiştirmez.

- **SpoofDPI** — [github.com/xvzc/SpoofDPI](https://github.com/xvzc/SpoofDPI), Apache License 2.0 altında, © Hyeon Kim ve katkıda bulunanlar. Runtime'da Homebrew aracılığıyla kurulur.

## Lisans

Bu repo'nun içeriği (wrapper script, installer, dokümantasyon) MIT Lisansı altında yayımlanmıştır. Bkz. [LICENSE](LICENSE).

SpoofDPI'nin kendisi Apache License 2.0 altında kalır ve bu proje tarafından değiştirilmemiştir.
