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
	m|max-up-time - Number of milliseconds after which to restart the app
	j|max-up-time-initial - Number of milliseconds after which to restart the app for the first time
	k|on-kill - Shell command executed upon process death
	s|on-restart - Shell command executed upon process restart
	x|on-http-fail - Shell command executed upon http monitor failure

#### Example Usage
	./bobby ./www -f -o "/log/www.log" -e "/log/www.log" -p "/run/www.pid" -h "http://mydomain.com/" -- --uid=www --gid=www --port=80 --access-log="/log/access_www.log" >> "/log/bobby_www.log" 2>&1