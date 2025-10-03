"""
app: Datadog Monitor
author: Your Name
summary: Displays Datadog trace stats
desc: Shows recent request statuses and a 24-hour summary of successful/failed requests from a Datadog trace search. Requires a companion Cloudflare Worker.
"""

load("render.star", "render")
load("schema.star", "schema")
load("http.star", "http")
load("encoding/json.star", "json")
load("time.star", "time")

# Default URL for the companion worker repository.
WORKER_INFO_URL = "https://github.com/addixon/datadog-tidbyt-worker"

def get_schema():
    """Gets the schema for the app config."""
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "worker_url",
                name = "Worker URL",
                desc = "The URL of your Cloudflare Worker.",
                icon = "globe",
            ),
            schema.Text(
                id = "auth_token",
                name = "Auth Token",
                desc = "The Bearer token for your worker.",
                icon = "key",
            ),
            schema.Text(
                id = "info",
                name = "Worker Info",
                desc = "Click below for setup instructions.",
                icon = "info",
                default = WORKER_INFO_URL,
            ),
        ],
    )

def main(config):
    """App entrypoint."""
    worker_url = config.get("worker_url")
    auth_token = config.get("auth_token")

    if not worker_url or not auth_token:
        print("DATADOG APP ERROR: Worker URL or Auth Token not set in config.")
        return render.Root(
            child = render.Text("Missing Config"),
        )

    # Fetch data from the Cloudflare Worker
    print("DATADOG APP: Fetching data from %s" % worker_url)
    rep = http.get(
        url = worker_url,
        headers = {
            "Authorization": "Bearer " + auth_token,
        },
    )

    print("DATADOG APP: Received status code %d" % rep.status_code)

    if rep.status_code != 200:
        print("DATADOG APP ERROR: Non-200 status code. Body: %s" % rep.body())
        return render.Root(
            child = render.Column(
                children=[
                    render.Text("HTTP Error:"),
                    render.Text(str(rep.status_code)),
                ]
            ),
        )

    raw_body = rep.body()
    print("DATADOG APP: Raw response body: %s" % raw_body)

    # Starlark doesn't have try/except, so we check if the body is valid JSON-like
    if not raw_body.startswith("{") or not raw_body.endswith("}"):
        print("DATADOG APP ERROR: Response is not valid JSON.")
        return render.Root(child = render.Text("Invalid JSON"))

    data = json.decode(raw_body)
    print("DATADOG APP: Decoded JSON data: %s" % data)

    now = time.now()
    minute = time.parse_time(now.to_string()).minute

    # Display recent requests for the first 2 minutes of the hour
    if minute < 2:
        return render_recent_requests(data.get("recent_requests", []))
    else:
        return render_summary(data.get("summary"))

def render_recent_requests(requests):
    """Renders the scrolling marquee view."""
    if not requests:
        return render.Root(
            child = render.Text("No requests in last 15m"),
        )

    children = []
    for req in requests:
        req_type = "RST" if "reset" in req.get("resource_name", "") else "XFR"
        status = req.get("status_code", "???")
        color = "#ff0000" if int(str(status)) >= 400 else "#ffffff" # Added str() for safety
        children.append(
            render.Text("%s:%s" % (req_type, status), color = color),
        )

    return render.Root(
        child = render.Marquee(
            width = 64,
            child = render.Row(
                main_align = "space_around",
                expanded = True,
                children = children,
            ),
        ),
    )

def render_summary(summary):
    """Renders the 24-hour summary view."""
    if not summary:
        return render.Root(
            child = render.Text("Summary data not available."),
        )

    reset = summary.get("reset", {})
    xfer = summary.get("transfer", {})

    return render.Root(
        child = render.Column(
            children = [
                render.Row(
                    children = [
                        render.Text("Reset: "),
                        render.Text(str(reset.get("success", 0)), color = "#00ff00"),
                        render.Text("/"),
                        render.Text(str(reset.get("fail", 0)), color = "#ff0000"),
                    ],
                ),
                render.Row(
                    children = [
                        render.Text("Xfer:  "),
                        render.Text(str(xfer.get("success", 0)), color = "#00ff00"),
                        render.Text("/"),
                        render.Text(str(xfer.get("fail", 0)), color = "#ff0000"),
                    ],
                ),
            ],
        ),
    )

