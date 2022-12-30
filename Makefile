export GO111MODULE=on

SQL_CMD:=mysql -h$(DB_HOST) -P$(DB_PORT) -u$(DB_USER) -p$(DB_PASS) $(DB_NAME)

NGX_LOG:=/var/log/nginx/access.log

MYSQL_HOST="127.0.0.1"
MYSQL_PORT=3306
MYSQL_USER=isucon
MYSQL_DBNAME=isucondition
MYSQL_PASS=isucon
MYSQL_LOG:=/var/log/mysql/slow.log

MYSQL=mysql -h$(MYSQL_HOST) -P$(MYSQL_PORT) -u$(MYSQL_USER) -p$(MYSQL_PASS) $(MYSQL_DBNAME)
SLOW_LOG=/tmp/slow-query.log

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

.PHONY: before
before:
	$(eval when := $(shell date "+%s"))

	ifeq ("$(wildcard $(NGX_LOG))", "")
		sudo mv $(NGX_LOG) /var/log/nginx/$(when) ; \
 	endif

	ifeq ("$(wildcard $(MYSQL_LOG))", "")
		sudo mv $(MYSQL_LOG) /var/log/mysql/$(when) ; \
 	endif

	bash config_setup.sh
	sudo systemctl restart nginx mysql

.PHONY: slow
slow:
	sudo pt-query-digest $(MYSQL_LOG) | $(SLACKCAT_MYSQL)

# mysqldumpslowを使ってslow wuery logを出力
# オプションは合計時間ソート
.PHONY: slow-show
slow-show:
	sudo mysqldumpslow -s t $(SLOW_LOG) | head -n 20 | $(SLACKCAT_MYSQL)


# alp

ALPSORT=sum
ALPM="/api/isu/.+/icon,/api/isu/.+/graph,/api/isu/.+/condition,/api/isu/[-a-z0-9]+,/api/condition/[-a-z0-9]+,/api/catalog/.+,/api/condition\?,/isu/........-....-.+"
OUTFORMAT=count,method,uri,min,max,sum,avg,p99

.PHONY: alp-cat
alp-cat:
	sudo alp ltsv --file=/var/log/nginx/access.log --sort $(ALPSORT) --reverse -o $(OUTFORMAT) -m $(ALPM) -q | $(SLACKCAT_ALP)

.PHONY: alpsave
alpsave:
	sudo alp ltsv --file=/var/log/nginx/access.log --pos /tmp/alp.pos --dump /tmp/alp.dump --sort $(ALPSORT) --reverse -o $(OUTFORMAT) -m $(ALPM) -q

.PHONY: alpload
alpload:
	sudo alp ltsv --load /tmp/alp.dump --sort $(ALPSORT) --reverse -o $(OUTFORMAT) -q

.PHONY: pprof
pprof:
	$(PPROF)
	$(SLACKCAT_BENCH) -n pprof.png ./pprof.png

.PHONY: pprof-web
pprof-web:
	go tool pprof -http=0.0.0.0:1080 $(BUILD_DIR)  http://localhost:6060/debug/pprof/profile

# slow-wuery-logを取る設定にする
# DBを再起動すると設定はリセットされる
.PHONY: slow-on
slow-on:
	sudo rm $(SLOW_LOG)
	sudo systemctl restart mysql
	$(MYSQL) -e "set global slow_query_log_file = '$(SLOW_LOG)'; set global long_query_time = 0.001; set global slow_query_log = ON;"

.PHONY: slow-off
slow-off:
	$(MYSQL) -e "set global slow_query_log = OFF;"

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
	
	# pt-query-digest
	wget https://github.com/percona/percona-toolkit/archive/refs/tags/3.5.0.tar.gz
	tar zxvf 3.5.0.tar.gz 
	sudo mv ./percona-toolkit-3.5.0/bin/pt-query-digest /usr/local/bin/pt-query-digest
	rm 3.5.0.tar.gz
	rm -rf percona-toolkit-3.5.0
	
	# for pprof
	sudo apt install graphviz

	# slackcat
	sudo curl -Lo slackcat https://github.com/bcicen/slackcat/releases/download/1.7.3/slackcat-1.7.3-$(uname -s | sed 's/.\+/\L\0/')-amd64
	sudo mv slackcat /usr/local/bin/
	sudo chmod +x /usr/local/bin/slackcat
