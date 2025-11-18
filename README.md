# SmartShelf Librarian

An intelligent library management system with IoT-enabled smart shelves, QR code door unlocking, and automated book issuing via weight sensors.

## 📚 Overview

SmartShelf Librarian revolutionizes the library experience by combining web technology with IoT hardware. Students can browse books online, scan QR codes to unlock shelf doors, and have books automatically issued to them when picked up - all without librarian intervention.

## ✨ Key Features

### For Students
- **Browse Books**: View all available books with cover images, authors, and shelf locations
- **Direct QR Pickup**: Click any book to open camera and scan shelf QR code
- **Automatic Door Unlock**: Servo motor unlocks door for 1 minute after successful QR scan
- **Auto-Issue System**: Weight sensors detect book removal and automatically issue it to your account
- **Borrowed Books Dashboard**: Track all currently borrowed books and due dates
- **Real-time Updates**: Dashboard updates instantly when books are issued

### For Librarians
- **Complete Dashboard**: Monitor all books, shelves, students, and issued books
- **Remote Door Control**: Unlock/lock any shelf door remotely via web interface
- **Real-time Shelf Status**: See which doors are currently locked/unlocked
- **Notifications**: Get instant alerts when students unlock doors
- **User Management**: Manage student accounts and roles
- **Book Catalog Management**: Add, edit, and remove books from the system

## 🛠️ Technology Stack

### Frontend
- **React 18** with TypeScript
- **Vite** for blazing-fast development
- **Tailwind CSS** + **shadcn/ui** for beautiful UI
- **html5-qrcode** for camera-based QR scanning
- **Supabase Client** for real-time database sync

### Backend
- **Supabase** (PostgreSQL + Auth + Realtime + Storage)
- **Row Level Security (RLS)** for secure multi-user access
- **Real-time subscriptions** for instant updates

### Hardware
- **ESP8266 NodeMCU** microcontroller
- **MG995 Servo Motor** for door lock mechanism
- **HX711 + Load Cell** for weight detection
- **HTTP Web Server** on ESP8266 for remote control

## 🚀 How It Works

### Student Flow (New Simplified Process)

1. **Browse Books** → Student opens app and sees all available books
2. **Click Book** → Click "Scan QR to Pickup" button on desired book
3. **Scan QR Code** → Camera opens, scan the QR code on the shelf door
4. **Door Unlocks** → Servo motor unlocks door automatically (1 minute window)
5. **Pick Up Book** → Remove book from shelf within 1 minute
6. **Auto-Issue** → Weight sensor detects removal, book automatically issued
7. **Door Auto-Locks** → Door locks automatically after 1 minute

### Librarian Flow

1. **Monitor System** → View all shelves, books, and borrowed items in real-time
2. **Remote Control** → Unlock/lock any shelf door directly from web interface
3. **Receive Notifications** → Get alerts when students access shelves
4. **Manage Catalog** → Add new books, update details, remove old books

## 📦 Installation

### Prerequisites
- Node.js 18+ with npm/bun
- Supabase account
- Arduino IDE (for ESP8266 firmware)

### Frontend Setup

```bash
# Clone repository
git clone <YOUR_GIT_URL>
cd smartshelf-librarian

# Install dependencies (using bun)
bun install

# Or using npm
npm install

# Set up environment variables
cp .env.example .env.local
# Edit .env.local with your Supabase credentials

# Start development server
bun dev
# Or: npm run dev
```

### Database Setup

1. Create a Supabase project at [supabase.com](https://supabase.com)
2. Run the migration files in `supabase/migrations/` in order
3. Enable Row Level Security (RLS) on all tables
4. Set up authentication (Email/Password enabled)

### Hardware Setup

See detailed guides in the `hardware/` folder:
- **CONNECTIONS.md** - Wiring diagrams for ESP8266, servo, and weight sensor
- **LIBRARIES_SETUP.md** - Arduino library installation instructions
- **esp8266_with_webserver.ino** - Upload this firmware to ESP8266

#### Quick Hardware Setup

1. Wire ESP8266 + Servo + HX711 according to CONNECTIONS.md
2. Install Arduino libraries (see LIBRARIES_SETUP.md)
3. Update WiFi credentials in .ino file
4. Upload firmware to ESP8266
5. Note the IP address (shown in Serial Monitor)
6. Update shelf's `esp_ip_address` in database

### QR Code Generation

1. Open `public/qr-code-generator.html` in browser
2. Enter shelf number (must match database)
3. Click "Generate QR Code"
4. Print and attach to shelf door

## 🔧 Configuration

### Environment Variables

```env
VITE_SUPABASE_URL=your_supabase_url
VITE_SUPABASE_ANON_KEY=your_supabase_anon_key
```

### ESP8266 Configuration

Edit `hardware/esp8266_with_webserver.ino`:

```cpp
const char* ssid = "Your_WiFi_SSID";
const char* password = "Your_WiFi_Password";
const unsigned long DOOR_TIMEOUT = 60000; // 1 minute
```

## 📁 Project Structure

```
smartshelf-librarian/
├── src/
│   ├── components/
│   │   ├── BookCard.tsx          # Book display with QR scan button
│   │   ├── QRScanner.tsx         # Camera-based QR scanner
│   │   ├── ShelfDoorControl.tsx  # Librarian door control panel
│   │   └── ui/                   # shadcn/ui components
│   ├── pages/
│   │   ├── BooksPage.tsx         # Book catalog
│   │   ├── StudentDashboard.tsx  # Student borrowed books
│   │   ├── LibrarianDashboard.tsx # Librarian admin panel
│   │   └── Auth.tsx              # Login/Register
│   ├── hooks/
│   │   └── useAuth.tsx           # Authentication hook
│   └── integrations/
│       └── supabase/             # Supabase client & types
├── hardware/
│   ├── CONNECTIONS.md            # Wiring guide
│   ├── LIBRARIES_SETUP.md        # Library installation
│   └── esp8266_with_webserver.ino # ESP8266 firmware
├── supabase/
│   └── migrations/               # Database migrations
└── public/
    └── qr-code-generator.html    # QR code generator tool
```

## 🔐 Security

- **Row Level Security (RLS)** on all Supabase tables
- **User roles**: Student, Librarian, Admin
- **Protected routes** - requires authentication
- **Secure ESP8266 HTTP endpoints** (consider HTTPS for production)

## 📱 API Endpoints

### ESP8266 HTTP API

```
GET  /status         - Get door lock status
POST /unlock         - Unlock door (60 second timeout)
POST /lock           - Lock door immediately
GET  /                - Web interface
```

### Supabase Tables

- `books` - Book catalog
- `shelves` - Shelf information (includes ESP IP)
- `issued_books` - Borrowed books tracking
- `users` - User accounts
- `notifications` - Real-time alerts

## 🧪 Testing

### Frontend Testing
```bash
bun run build    # Check for TypeScript errors
bun run lint     # Run ESLint
```

### Hardware Testing
1. Open Serial Monitor (115200 baud)
2. Check ESP8266 connects to WiFi
3. Note IP address displayed
4. Test unlock endpoint: `http://<ESP_IP>/unlock`
5. Verify servo moves and door unlocks

## 🚀 Deployment

### Frontend Deployment

Deploy to Vercel/Netlify/Lovable:

```bash
# Build production bundle
bun run build

# Deploy to Lovable
# Visit: https://lovable.dev/projects/7181e1d8-c434-4e28-b051-2dba373d1a56
```

### ESP8266 Deployment

1. Upload firmware via USB
2. Ensure stable power supply (servo needs 5V 2A+)
3. Configure static IP on router (recommended)
4. Update `esp_ip_address` in database

## 📝 License

MIT License - See LICENSE file for details

## 🤝 Contributing

Contributions welcome! Please open issues or pull requests.

## 📧 Support

For questions or issues, please open a GitHub issue or contact the development team.

---

**Built with ❤️ for modern libraries**
