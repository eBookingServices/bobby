module monitor;

import core.memory;

import std.array;
import std.conv;
import std.datetime;
import std.regex;
import std.socket;
import std.string;
import std.stdio;


alias Now = Clock.currTime;


struct URL {
	static URL parse(string url) {
		auto matches = matchFirst(url, ctRegex!(r"^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?$", "i"));

		URL result;
		if (!matches.empty) {
			result.protocol = matches[2].toLower;
			auto host = matches[4].toLower;
			auto index = host.indexOf(':');

			if (index != -1) {
				result.port = host[index + 1..$].to!ushort;
				result.host = host[0..index];
			} else {
				switch(result.protocol) {
				case "http":
					result.port = 80;
					break;
				case "https":
					result.port = 443;
					break;
				default:
					break;
				}
				result.host = host;
			}

			result.path = matches[5];
			result.query = matches[7];
			result.anchor = matches[9];
		}

		return result;
	}

	string protocol;
	string host;
	ushort port;
	string path;
	string query;
	string anchor;
}


struct HTTPMonitor {
	enum State : uint {
		Reset,
		Ready,
		Idle,
		Connect,
		Connecting,
		Connected,
		Request,
		Requesting,
		Requested,
		Success,
		Failure,
		GraceFailure,
	}

	~this() {
		reset();
	}

	void reset() {
		close();
		try_ = 0;

		changeState(State.Reset);
	}

	void start(string url, size_t intervalMS, size_t timeoutMS, size_t graceMS, size_t retries) {
		url_ = URL.parse(url);
		timeoutMS_ = timeoutMS;
		intervalMS_ = intervalMS;
		graceMS_  = graceMS;
		retryCount_ = retries;

		close();
		try_ = 0;

		changeState(State.Ready);
		monitorStart_ = Now;
	}

	private void close() {
		if (socket_ !is null) {
			socket_.shutdown(SocketShutdown.SEND);
			socket_.close();

			destroy(socket_);
			socket_ = null;

			GC.collect();
		}
	}

	private void changeState(State state) {
		state_ = state;
	}

	void update() {
		final switch (state_) with (State) {
		case Reset:
			break;

		case Ready:
			changeState(Connect);
			goto case Connect;

		case Idle:
			if (((Now - testStart_).total!"msecs" >= intervalMS_)) {
				changeState(Connect);
				goto case Connect;
			}
			break;

		case Connect:
			assert(socket_ is null);
			try {
				testStart_ = Now;
				socket_ = new TcpSocket();
				socket_.blocking = false;

				socket_.connect(new InternetAddress(url_.host, url_.port));

				changeState(Connecting);
				goto case Connecting;
			} catch (Throwable e) {
				writeln(e.toString);
				changeState(Failure);
				goto case Failure;
			}

		case Connecting:
			changeState(Connected);
			goto case Connected;

		case Connected:
			changeState(Request);
			goto case Request;

		case Request:
			if (request_.empty) {
				auto app = appender!string;

				app.put("GET ");
				app.put(url_.path.empty ? "/" : url_.path);
				if (!url_.query.empty) {
					app.put("?");
					app.put(url_.query);
				}
				app.put(" HTTP/1.1\r\n\r\n");

				request_ = cast(ubyte[])app.data.idup;
			}

			try {
				auto result = socket_.send(request_);

				if (result == Socket.ERROR) {
					if ((Now - testStart_).total!"msecs" >= timeoutMS_) {
						changeState(Failure);
						goto case Failure;
					}
					break;
				}

				received_.length = 0;

				changeState(Requesting);
				goto case Requesting;
			} catch {
				changeState(Failure);
				goto case Failure;
			}

		case Requesting:
			ubyte[32] buf;

			auto result = socket_.receive(buf);
			if (result > 0) {
				received_ ~= buf[0..result];
				if (received_.length > 12) {
					changeState(Requested);
					goto case Requested;
				}
			} else if (result == Socket.ERROR) {
				if ((Now - testStart_).total!"msecs" >= timeoutMS_) {
					changeState(Failure);
					goto case Failure;
				}
				break;
			} else if (result == 0) {
				changeState(Requested);
				goto case Requested;
			}
			break;

		case Requested:
			if (statusOK()) {
				changeState(Success);
				goto case Success;
			}
			changeState(Failure);
			goto case Failure;

		case Success:
			close();
			try_ = 0;

			changeState(Idle);
			goto case Idle;

		case Failure:
			close();
			++try_;

			if ((try_ <= retryCount_) || ((Now - monitorStart_).total!"msecs" <= graceMS_)) {
				changeState(GraceFailure);
				goto case GraceFailure;
			}
			break;

		case GraceFailure:
			if ((Now - monitorStart_).total!"msecs" <= graceMS_)
				try_ = 0;

			changeState(Idle);
			goto case Idle;
		}
	}

	private bool statusOK() {
		if (received_.length <= 12)
			return false;


		if ((received_.ptr[0] != 'H') || (received_.ptr[1] != 'T') || (received_.ptr[2] != 'T') || (received_.ptr[3] != 'P') || (received_.ptr[4] != '/'))
			return false;

		if (received_.ptr[8] != ' ')
			return false;

		if (received_.ptr[9] == '5')
			return false;
		return true;
	}

	@property State state() {
		return state_;
	}

private:
	URL url_;

	size_t timeoutMS_;
	size_t intervalMS_;
	size_t graceMS_;
	size_t retryCount_;
	size_t try_;

	ubyte[] request_;
	ubyte[] received_;

	SysTime monitorStart_;
	SysTime testStart_;

	State state_ = State.Ready;
	Socket socket_;
}
