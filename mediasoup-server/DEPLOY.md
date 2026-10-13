# BESTIE Mediasoup Production

## 1. Ubuntu
apt update && apt upgrade -y
apt install -y nginx ufw

## 2. Node 22
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs

## 3. Install
cd /opt/bestie/mediasoup-server
npm install --omit=dev

## 4. Environment
cp .env.example .env
nano .env
Set MEDIASOUP_ANNOUNCED_IP to the VPS public IPv4.
Never commit .env.

## 5. Firewall
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 4000/tcp
ufw allow 20000:20100/tcp
ufw allow 20000:20100/udp
ufw --force enable

## 6. Start with systemd
cp systemd/bestie-mediasoup.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now bestie-mediasoup
systemctl status bestie-mediasoup
journalctl -u bestie-mediasoup -f

## 7. Nginx
cp nginx/bestie-mediasoup.conf /etc/nginx/sites-available/bestie-mediasoup
ln -s /etc/nginx/sites-available/bestie-mediasoup /etc/nginx/sites-enabled/bestie-mediasoup
nginx -t && systemctl reload nginx

## 8. TLS
certbot --nginx -d YOUR_DOMAIN

Flutter production signaling URL:
wss://YOUR_DOMAIN
