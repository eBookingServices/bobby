import core.thread;

import std.algorithm;
import std.array;
import std.c.stdlib;
import std.conv;
import std.datetime;
import std.file;
import std.getopt;
import std.json;
import std.path;
import std.process;
import std.range;
import std.string;
import std.stdio;


import monitor;



struct App {
	string exe;
	string[] args;
	string workingDir;
	string stdoutFileName;
	string stderrFileName;
	string pidFileName;

	string httpMonitorURL;
	size_t httpMonitorInterval;
	size_t httpMonitorTimeout;
	size_t httpMonitorGrace;
	size_t httpMonitorRetries;

	size_t uptimeMax;
	size_t uptimeMaxInitial;

	string onKill;
	string onRestart;
	string onHTTPFail;
	string onMaxUptime;

	string monitorFileModification;
	size_t monitorFileModificationPeriod;
	string onNoMonitorFileModification;

	size_t flags;
	size_t starts;
	SysTime started;
	size_t delay;

	HTTPMonitor httpMonitor;

	Pid pid;
	File stdout;
	File stderr;
}


void trigger(string cmd) {
	if (!cmd.empty) {
		try {
			spawnShell(cmd);
		} catch (Throwable e) {
			bark(e.msg);
		}
	}
}


void bark(string error) {
	std.stdio.stderr.write(format("[%s bark] %s\n", Clock.currTime.toSimpleString, error));
}


private size_t parseAppFlag(string value) {
	switch (value.toLower) {
	default: return 0;
	}
}


bool isExternal(string path) {
	return !path.empty && !path.isAbsolute && (path.length > 1) && (path[0..2] == "..");
}


string fix(string path) {
	if (path.isAbsolute) {
		auto relative = path.relativePath(cwd_);
		if (!relative.isExternal)
			path = relative;
	}

	string result = buildNormalizedPath(path);
	if (!result.length)
		result = ".";
	return result;
}


string absolute(string path) {
	if (!path.isAbsolute)
		path = buildNormalizedPath(cwd_, path);
	return path;
}


void killit(ref App app) {
	app.killMonitors;

	if (app.pid) {
		try {
			bark(format("killing %s (%d)...", baseName(app.exe), app.pid.processID));

			version(Posix)app.pid.kill(SIGKILL);
			else app.pid.kill;

			app.pid.wait;
			app.pid.destroy;

			trigger(app.onKill);
		} catch (Throwable e) {
			bark(e.msg);
		}

		try {
			if (!app.pidFileName.empty && exists(app.pidFileName))
				remove(app.pidFileName);
		} catch (Throwable e) {
			bark(e.msg);
		}
	}
}


void startMonitors(ref App app) {
	if (!app.httpMonitorURL.empty) {
		app.httpMonitor.start(app.httpMonitorURL, app.httpMonitorInterval, app.httpMonitorTimeout, app.httpMonitorGrace, app.httpMonitorRetries);
		bark(format("HTTP monitor started for %s (%d) (%s)...", baseName(app.exe), app.pid.processID, app.httpMonitorURL));
	}
}

void killMonitors(ref App app) {
	if (!app.httpMonitorURL.empty)
		app.httpMonitor.reset;
}

void updateMonitors(ref App app) {
	if (!app.httpMonitorURL.empty)
		app.httpMonitor.update;
}


bool alive(ref App app) {
	if (app.pid is null)
		return false;

	auto status = tryWait(app.pid);
	if (status.terminated) {
		app.pid.destroy;
		app.pid = null;
		return false;
	}

	if (!app.httpMonitorURL.empty && (app.httpMonitor.state == HTTPMonitor.State.Failure)) {
		bark(format("HTTP failed to get %s for %s (%s)", app.httpMonitorURL, baseName(app.exe), app.pid.processID));
		trigger(app.onHTTPFail);
		return false;
	}

	auto uptimeMax = ((app.starts == 1) && app.uptimeMaxInitial) ? app.uptimeMaxInitial : app.uptimeMax;
	if (uptimeMax && ((Now - app.started) >= uptimeMax.msecs)) {
		bark(format("restarting %s (%d) after max uptime of %d milliseconds reached...", baseName(app.exe), app.pid.processID, app.uptimeMax));
		trigger(app.onMaxUptime);
		return false;
	}

	if (!app.monitorFileModification.empty && (Now - app.started) > app.monitorFileModificationPeriod.seconds) {
		SysTime accessTime;
		SysTime modificationTime;
		getTimes(app.monitorFileModification, accessTime, modificationTime);
		if((Now - modificationTime) > app.monitorFileModificationPeriod.seconds)
		{
			bark("Restarting %s (%s) : Monitored file '%s' was not modified within the expected period (%d seconds)".format(baseName(app.exe), app.pid.processID, app.monitorFileModification, app.monitorFileModificationPeriod));
			trigger(app.onNoMonitorFileModification);
			return false;			
		}
	}

	return true;
}


void spawn(ref App app) {
	auto execute = app.exe;
	auto workingDir = app.workingDir.length ? app.workingDir : cwd_;
	if (!workingDir.isAbsolute)
		workingDir = buildNormalizedPath(cwd_, workingDir);

	auto args = [ execute ] ~ app.args;

	try {
		args[0] = args[0].absolute;

		++app.starts;
		app.started = Clock.currTime;

		app.pid = spawnProcess(args, std.stdio.stdin, app.stdout, app.stderr, null, Config.inheritFDs | Config.retainStdout | Config.retainStderr, workingDir);
	} catch(Throwable e) {
		bark(e.msg);
	}

	if (app.alive) {
		bark(format("app started %s (%d) (x%d)...", baseName(app.exe), app.pid.processID, app.starts));
		if (app.starts > 1)
			trigger(app.onRestart);

		app.startMonitors;

		if (!app.pidFileName.empty) {
			try {
				std.file.write(app.pidFileName, app.pid.processID.to!string);
			} catch (Throwable e) {
				bark(e.msg);
			}
		}
	} else {
		bark(format("failed to start %s...", baseName(app.exe)));
	}
}

extern(C) void signalHandler(int sig) {
	try {
		app_.killit;

		std.stdio.stdout.flush;
		std.stdio.stderr.flush;
	} catch {
	}

	exit(0);
}

version(Posix) {
	import core.sys.posix.signal;
	void installSignalHandlers() {
		sigset_t sigset;
		sigemptyset(&sigset);
		sigaction_t siginfo;
		siginfo.sa_handler = &signalHandler;
		siginfo.sa_mask = sigset;
		siginfo.sa_flags = 0;

		sigaction(SIGKILL, &siginfo, null);
		sigaction(SIGINT, &siginfo, null);
		sigaction(SIGTERM, &siginfo, null);
	}
} else {
	import core.stdc.signal;
	void installSignalHandlers() {
		import std.traits;
		signal(SIGABRT, cast(ParameterTypeTuple!signal[1])&signalHandler);
		signal(SIGTERM, cast(ParameterTypeTuple!signal[1])&signalHandler);
		signal(SIGINT, cast(ParameterTypeTuple!signal[1])&signalHandler);
	}
}


__gshared  {
	App app_;
	string cwd_;
}


int main(string[] args) {
	installSignalHandlers;

	cwd_ = buildNormalizedPath(getcwd);

	bool force = false;

	string pidFile;
	string stdoutFile;
	string stderrFile;
	string workingDir;
	string httpMonitorURL;
	size_t httpMonitorInterval = 5000;
	size_t httpMonitorTimeout = 2500;
	size_t httpMonitorGrace = 25000;
	size_t httpMonitorRetries = 3;

	size_t uptimeMax = 0;
	size_t uptimeMaxInitial = 0;

	string onKill;
	string onRestart;
	string onHTTPFail;
	string onMaxUptime;

	string monitorFileModification;
	size_t monitorFileModificationPeriod = 300;
	string onNoMonitorFileModification;

	try {
		auto opts = getopt(args,
			"f|force", "Force execution even if pid file is still present", &force,
			"p|pid-file", "Path of the .pid file", &pidFile,
			"o|stdout-file", "File to use as stdout - can be the same as stderr", &stdoutFile,
			"e|stderr-file", "File to use as stderr - can be the same as stdout", &stderrFile,
			"w|working-dir", "Working directory", &workingDir,
			"m|max-up-time", "Number of seconds after which to restart the app", &uptimeMax,
			"j|max-up-time-initial", "Number of seconds after which to restart the app for the first time", &uptimeMaxInitial,
			"u|monitor-http-url", "URL to monitor for HTTP availability", &httpMonitorURL,
			"i|monitor-http-interval", "HTTP monitor request interval in milliseconds", &httpMonitorInterval,
			"t|monitor-http-timeout", "HTTP monitor request timeout in milliseconds", &httpMonitorTimeout,
			"g|monitor-http-grace", "HTTP monitor initial grace period during which failures are ignored", &httpMonitorGrace,
			"r|monitor-http-retries", "HTTP monitor number of retries before considering a failure", &httpMonitorRetries,
			"k|on-kill", "Shell command executed upon process death", &onKill,
			"s|on-restart", "Shell command executed upon process restart", &onRestart,
			"x|on-http-fail", "Shell command executed upon http monitor failure", &onHTTPFail,
			"z|on-max-uptime", "Shell command executed upon restart due to max uptime", &onMaxUptime,
			"mf|monitor-file", "File to monitor for periodical modifications ", &monitorFileModification,
			"mfp|monitor-file-period", "Expected time (in seconds) for file modifications", &monitorFileModificationPeriod,
			"mff|on-no-monitor-file-fail", "Shell command executed when the monitored file has not been modified", &onNoMonitorFileModification,
		);


		if (opts.helpWanted || (args.length < 2)) {
			defaultGetoptPrinter("Usage: bobby [OPTIONS] executable [-- executable args] \n", opts.options);
			return 1;
		}
	} catch (Exception e) {
		writeln("Error: ", e.msg);
		return 1;
	}

	app_ = App(args[1], args[2..$], workingDir, stdoutFile, stderrFile, pidFile,
			httpMonitorURL, httpMonitorInterval, httpMonitorTimeout, httpMonitorGrace,
			httpMonitorRetries, uptimeMax, uptimeMaxInitial, onKill, onRestart, onHTTPFail, onMaxUptime,
			monitorFileModification, monitorFileModificationPeriod, onNoMonitorFileModification
		);

	try {
		if (!app_.stdoutFileName.empty) {
			app_.stdout.open(app_.stdoutFileName, "a");
		} else {
			app_.stdout = std.stdio.stdout;
		}

		if (!app_.stderrFileName.empty) {
			if (app_.stderrFileName == app_.stdoutFileName) {
				app_.stderr = app_.stdout;
			} else {
				app_.stderr.open(app_.stderrFileName, "a");
			}
		} else {
			app_.stderr = std.stdio.stderr;
		}

		if (!app_.pidFileName.empty && exists(app_.pidFileName)) {
			if (!force) {
				bark(format("%s exists - the process may be running!\nRemove it manually or use --force to ignore it.", app_.pidFileName));
				return 1;
			}

			bark(format("deleting %s...", app_.pidFileName));
			remove(app_.pidFileName);
		}
	} catch (Throwable e) {
		bark(e.msg);
		return 1;
	}

	while (true) {
		auto now = Now;
		if (!app_.alive) {
			if (!app_.starts) {
				app_.spawn;
			} else {
				if ((now - app_.started) > app_.delay.seconds) {
					app_.killit;
					app_.spawn;
					app_.delay = min(max(1, app_.delay) * 2, 60);
				}
			}
		} else {
			if ((now - app_.started) > 2.seconds)
				app_.delay = 0;

			app_.updateMonitors;
		}

		Thread.sleep(100.msecs);
	}
}
