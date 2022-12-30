export GO111MODULE=on

SQL_CMD:=mysql -h$(DB_HOST) -P$(DB_PORT) -u$(DB_USER) -p$(DB_PASS) $(DB_NAME)

NGX_LOG:=/var/log/nginx/access.log

MYSQL_HOST="127.0.0.1"
MYSQL_PORT=3306
MYSQL_USER=isuconp
MYSQL_DBNAME=isuconp
MYSQL_PASS=isuconp
MYSQL_LOG:=/var/log/mysql/mysql-slow.log

MYSQL=mysql -h$(MYSQL_HOST) -P$(MYSQL_PORT) -u$(MYSQL_USER) -p$(MYSQL_PASS) $(MYSQL_DBNAME)

SLACKCAT:=slackcat --tee --channel general
SLACKCAT_MYSQL:=slackcat --tee --channel mysql-slow-query
SLACKCAT_ALP:=slackcat --channel alp-log
SLACKCAT_BENCH:=slackcat --channel bench-result

PPROF:=go tool pprof -png -output pprof.png http://localhost:6060/debug/pprof/profile
PPROF_WEB:=go tool pprof -http=0.0.0.0:1080 webapp/go  http://localhost:6060/debug/pprof/profile

PROJECT_ROOT:=/home/isucon/
BUILD_DIR:=/home/isucon/private_isu/webapp/golang

CA:=-o /dev/null -s -w "%{http_code}\n"

.PHONY:restart-go
restart-go:
	sudo systemctl restart isu-go.service

.PHONY: dev
dev: 
	bash $(BUILD_DIR)/setup.sh; \
	sudo systemctl restart isu-go.service

.PHONY: bench-dev
bench-dev: commit before slow-on dev

.PHONY: bench
bench: 
	/home/isucon/private_isu/benchmarker/bin/benchmarker -u /home/isucon/private_isu/benchmarker/userdata -t http://localhost | $(SLACKCAT_BENCH)

.PHONY: log
log: 
	sudo journalctl -u isucari.golang -n10 -f

.PHONY: push
push: 
	git push

.PHONY: commit
commit:
	cd $(PROJECT_ROOT); \
	git add .; \
	git commit --allow-empty -m "bench"

.PHONY: config-set
config-set:
	sudo cp webapp/etc/nginx/nginx.conf /etc/nginx/nginx.conf
	sudo nginx -t

	sudo cp webapp/etc/my.cnf /etc/mysql/my.cnf

	sudo cp webapp/etc/sysctl.conf /etc/sysctl.conf
	sudo sysctl -p

	sudo systemctl restart nginx mysql

.PHONY: before
before:
	sudo mv $(NGX_LOG) $(NGX_LOG).`date "+%Y%m%d-%H%M%S"`
	sudo mv $(MYSQL_LOG) $(MYSQL_LOG).`date "+%Y%m%d-%H%M%S"`
	sudo systemctl restart nginx mysql

# mysqldumpslowを使ってslow wuery logを出力
# オプションは合計時間ソート
.PHONY: slow
slow:
	sudo mysqldumpslow -s t $(MYSQL_LOG) | head -n 20 | $(SLACKCAT_MYSQL)

# alp

ALPSORT=sum
ALPM="/api/isu/.+/icon,/api/isu/.+/graph,/api/isu/.+/condition,/api/isu/[-a-z0-9]+,/api/condition/[-a-z0-9]+,/api/catalog/.+,/api/condition\?,/isu/........-....-.+"
OUTFORMAT=count,method,uri,min,max,sum,avg,p99

.PHONY: alp-cat
alp-cat:
	sudo alp json --file=/var/log/nginx/access.log --sort $(ALPSORT) --reverse -o $(OUTFORMAT) -m $(ALPM) -q | $(SLACKCAT_ALP)

.PHONY: pprof
pprof:
	$(PPROF)
	$(SLACKCAT_BENCH) -n pprof.png ./pprof.png

.PHONY: pprof-web
pprof-web:
	go tool pprof -http=0.0.0.0:1080 $(BUILD_DIR)  http://localhost:6060/debug/pprof/profile

.PHONY: ab-test
ab-test:
	ab -c 1 -n 10 http://localhost/ | $(SLACKCAT_ALP)

.PHONY: setup
setup:
	sudo apt update
	sudo apt install -y git unzip htop bash-completion apache2-utils
	
	# go
	wget https://golang.org/dl/go1.19.4.linux-amd64.tar.gz
	rm -rf /usr/local/go
	sudo tar -C /usr/local/ -xzf go1.19.4.linux-amd64.tar.gz
	rm go1.19.4.linux-amd64.tar.gz*
	
	# alp
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.12/alp_linux_amd64.zip
	unzip alp_linux_amd64.zip
	sudo install ./alp /usr/local/bin/
	rm -rf  alp*	
		
	# for pprof
	sudo apt install graphviz

	# slackcat
	sudo curl -Lo slackcat https://github.com/bcicen/slackcat/releases/download/1.7.3/slackcat-1.7.3-$(uname -s | sed 's/.\+/\L\0/')-amd64
	sudo mv slackcat /usr/local/bin/
	sudo chmod +x /usr/local/bin/slackcat
