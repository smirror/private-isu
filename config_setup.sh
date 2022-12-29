sudo cp webapp/etc/nginx/nginx.conf /etc/nginx/nginx.conf
sudo nginx -t

sudo cp webapp/etc/my.cnf /etc/mysql/my.cnf
sudo cp webapp/etc/sysctl.conf /etc/sysctl.conf
sudo sysctl -p
