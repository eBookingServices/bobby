# bobby
Simple process and HTTP availability monitor

#### Options

	f|force - Force execution even if .pid file is still present
	p|pid-file - Path of the .pid file
	o|stdout-file - File to use as stdout - can be the same as stderr
	e|stderr-file - File to use as stderr - can be the same as stdout
	w|working-dir - Working directory
	h|monitor-http-url - URL to monitor for HTTP availability

#### Example Usage
	./bobby ./www -f --stdout-file="/log/www.log" --stderr-file="/log/www.log" --pid-file="/run/www.pid" --monitor-http-url="http://mydomain.com/" -- --uid=www --gid=www --port=80 --access-log="/log/access_www.log" >> "/log/bobby_www.log" 2>&1


#### TODO
- Add support for event notifications (alert email, post url, run script)
- More configuration for HTTP monitor - grace period length, number or retries, timeout, ...
