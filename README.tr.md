<p align="center"><sub><a href="README.md">English</a> · <b>Türkçe</b></sub></p>

<h1 align="center">
  <img src="public/icon.svg" alt="" width="44" valign="middle" />
  &nbsp;Meridian
</h1>

<p align="center"><i>Hayatınız, mükemmel bir şekilde düzenlenmiş.</i></p>

<p align="center">
  <img src="https://img.shields.io/badge/Ruby-3.3-CC342D?logo=ruby&logoColor=white" alt="Ruby 3.3">
  <img src="https://img.shields.io/badge/Rails-8-CC0000?logo=rubyonrails&logoColor=white" alt="Rails 8">
  <img src="https://img.shields.io/badge/PostgreSQL-14+-4169E1?logo=postgresql&logoColor=white" alt="PostgreSQL 14+">
  <img src="https://img.shields.io/badge/Hotwire-Turbo%20%2B%20Stimulus-5a67d8" alt="Hotwire">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20NC%201.0.0-blue" alt="License"></a>
</p>

<p align="center">
  <a href="#-h%C4%B1zl%C4%B1-ba%C5%9Flang%C4%B1%C3%A7">Hızlı başlangıç</a> ·
  <a href="#-%C3%B6zellikler">Özellikler</a> ·
  <a href="#-yedekleme--geri-y%C3%BCkleme">Yedekleme</a> ·
  <a href="#-klavye-k%C4%B1sayollar%C4%B1">Kısayollar</a>
</p>

---

Meridian, kendi makinende çalışan kişisel bir "yaşam OS"u. Genelde yarım düzine farklı aboneliğe dağılmış olan şeyleri — para, alışkanlıklar, görevler, takvim, günlük, hedefler — tek bir Rails uygulamasında bir araya getirir ve verinin tamamı senin kontrolündeki bir makinede kalır. Yedekleme tek bir `tar.gz`, yani veriyi taşımak kopyala-yapıştır kadar basit.

<p align="center">
  <img src="docs/dashboard.png" alt="Dashboard" width="100%" />
</p>

## ✨ Özellikler

- 💰 **Finans** — hesaplar, alt kategoriler ve üst-kategori toplamı, işlemler, **pace takipli aylık bütçeler**, abonelikler, etkileşimli harcama-dağılımı grafiği (hazır & özel tarih aralıkları, hesap filtresi, tıkla-detaya-in), 6 aylık trend, çoklu para birimi (gram-altın dahil), CSV dışa aktarım
- ✅ **Görevler** — listeler, öncelikler, son tarih, bugün / hafta / gecikmiş filtreleri
- 🔥 **Alışkanlıklar** — günlük ve haftalık tekrar, streak, 12 haftalık ısı haritası, tamamlanma oranı
- 📅 **Takvim** — aylık ızgara + sürükle-bırak ile haftalık görünüm, iCal akışı
- 📓 **Günlük** — zengin metin girişleri, mood, enerji, gratitude, etiketler
- 🎯 **Hedefler** — finansal / alışkanlık / özel hedefler, canlı hesaplanan ilerleme ve renk-kodlu son tarih rozetleri
- 🏠 **Dashboard** — bugünün alışkanlıkları, görevler, etkinlikler ve harcamayı tek bakışta gösteren bento ızgara
- 🔍 **Global arama** — `⌘K` ile tüm modüller arasında anında arama
- ⚡ **Hızlı yakalama** — tek bir input; sayılar işleme, `habit:` ile başlayanlar alışkanlık log'una, geri kalanı todo'ya düşer
- 📊 **Haftalık review** — otomatik özetlenmiş istatistikler eşliğinde rehberli yansıma
- 🍅 **Focus timer** — pomodoro, tarayıcı bildirimi ve görev başına süre takibi
- 📈 **Insights** — modüller arası örüntü: hafta içi ve hafta sonu harcaması, mood × alışkanlık ilişkisi, en verimli gün
- 💾 **Yedekleme & geri yükleme** — `pg_dump` + ActiveStorage blob'ları taşınabilir tek arşivde
- 🌍 **Çift dil** — tam Türkçe & İngilizce arayüz, kullanıcı başına değiştirilebilir
- 🎨 **Tasarım** — Fraunces + DM Sans, koyu öncelikli amber/altın palet, opsiyonel açık tema

## 🧰 Teknoloji

| Katman | Teknoloji |
|---|---|
| Backend | Ruby 3.3 · Rails 8 |
| Frontend | Hotwire (Turbo + Stimulus), Importmap, Tailwind v4 |
| Veritabanı | PostgreSQL 14+ |
| Arka plan / önbellek | Solid Queue · Solid Cache · Solid Cable (veritabanı tabanlı) |
| Auth | Devise |
| Grafik | Apache ECharts (finans paneli) · Chartkick + Chart.js · groupdate |
| Para | money-rails · çoklu para birimi, özel gram-altın (GAU) dahil |
| Tekrar kuralları | ice_cube |
| Yerelleştirme | Türkçe · İngilizce (Rails I18n) |
| Yedekleme | pg_dump · tar.gz · ActiveStorage |
| Test | RSpec · FactoryBot · Shoulda · Capybara · SimpleCov |
| Lint / güvenlik | RuboCop (omakase + rspec) · Brakeman · EagerEye (statik N+1) |

## 🚀 Hızlı Başlangıç

**Gereksinimler** — Ruby 3.3.x (`rbenv` / `asdf` üzerinden), PostgreSQL 14+, Node.js 22+ (yalnızca Tailwind native binary için).

```bash
git clone <your-repo> meridian
cd meridian
bundle install
bin/rails db:create db:migrate db:seed
bin/dev
```

<http://localhost:3000> aç. Seed iki kullanıcı oluşturur:

- `admin@meridian.local` / `password123`
- `demo@meridian.local` / `demo12345` — alışkanlık, hedef, işlem ve günlük girdileriyle hazır

### Test, lint, güvenlik

```bash
bin/rspec
bundle exec rubocop
bundle exec brakeman -i config/brakeman.ignore
```

## 💾 Yedekleme & Geri Yükleme

Yedekleme bu projede birinci sınıf bir özellik: "senin Meridian'ını" tanımlayan her şey — şema, kayıtlar, dosyalar, uygulama versiyonu — tek bir arşivde toplanır.

**Oluşturma**

1. **Ayarlar → Veri** sekmesine git veya doğrudan `/backups` adresini aç.
2. **Yedek oluştur**'a tıkla.
3. Listeden `.tar.gz` dosyasını indir.

Arşivin içinde:

- `db.dump` — tam PostgreSQL dump (custom format)
- `storage/` — tüm ActiveStorage blob'ları (avatarlar, günlük ekleri)
- `metadata.json` — Meridian versiyonu, şema versiyonu, zaman damgası

**Geri yükleme** — yeni makineye yukarıdaki adımlarla Meridian'ı kur, `/backups` sayfasına git, arşivi **Restore** kartına bırak, onayla. Uygulama oturumu kapatır; eski kullanıcı bilgilerinle tekrar giriş yap.

> ⚠️ Geri yükleme mevcut veritabanını siler. Saklamak istediğin bir şey varsa önce yeni bir yedek al.

Arşiv yapısının tamamı: [docs/backup_format.md](docs/backup_format.md).

## ⌨️ Klavye Kısayolları

| | |
|---|---|
| `⌘K` / `Ctrl+K` / `/` | Global arama |
| `c` | Hızlı yakalama |
| `g d` · `g f` · `g t` · `g h` | Dashboard · Finans · Görevler · Alışkanlıklar |
| `g c` · `g j` · `g g` | Takvim · Günlük · Hedefler |
| `Esc` | Açık modal'ı kapat |

## 📂 Modül Haritası

```
Dashboard       (/)
├─ Finans       (/finance)
│  ├─ İşlemler, Hesaplar, Kategoriler, Bütçeler, Abonelikler
│  └─ Raporlar, CSV dışa aktarım
├─ Görevler     (/todos), Listeler (/todo_lists)
├─ Alışkanlıklar (/habits)
├─ Takvim       (/calendar) — ay + hafta, /calendar/feed üzerinden iCal akışı
├─ Günlük       (/journal)
├─ Hedefler     (/goals)
├─ Insights     (/insights)
├─ Haftalık review (/weekly_reviews)
├─ Yedekler     (/backups)
└─ Ayarlar      (/settings)
```

## 📄 Lisans

Meridian, [**PolyForm Noncommercial License 1.0.0**](LICENSE) altında dağıtılır. Kişisel, akademik, eğitim ve ticari olmayan her tür kullanım serbesttir; ticari kullanım bu lisansla verilmez. Farklı bir anlaşma istiyorsan issue açabilirsin.

---

<p align="center"><sub>Meridian — hayatınız, mükemmel bir şekilde düzenlenmiş.</sub></p>
