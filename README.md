# bobby
Simple process and HTTP availability monitor

#### Options

	f|force - Force execution even if .pid file is still present
	p|pid-file - Path of the .pid file
	o|stdout-file - File to use as stdout - can be the same as stderr
	e|stderr-file - File to use as stderr - can be the same as stdout
	w|working-dir - Working directory
	u|monitor-http-url - URL to monitor for HTTP availability
	i|monitor-http-interval - HTTP monitor request interval in milliseconds
	t|monitor-http-timeout - HTTP monitor request timeout in milliseconds
	g|monitor-http-grace - HTTP monitor initial grace period during which failures are ignored
	r|monitor-http-retries - HTTP monitor number of retries before considering a failure

#### Example Usage
	./bobby ./www -f -o "/log/www.log" -e "/log/www.log" -p "/run/www.pid" -h "http://mydomain.com/" -- --uid=www --gid=www --port=80 --access-log="/log/access_www.log" >> "/log/bobby_www.log" 2>&1


#### TODO
- Add support for event notifications (alert email, post url, run script)
- More configuration for HTTP monitor - grace period length, number or retries, timeout, ...
