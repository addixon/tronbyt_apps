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
            # CORRECTED: Changed schema.Password to schema.Text for compatibility.
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
        return render.Root(
            child = render.Text("Worker URL or Auth Token not set."),
        )

    # Fetch data from the Cloudflare Worker
    rep = http.get(
        url = worker_url,
        headers = {
            "Authorization": "Bearer " + auth_token,
        },
    )

    if rep.status_code != 200:
        return render.Root(
            child = render.Text("Error: %s" % rep.body()),
        )

    data = json.decode(rep.body())
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
        color = "#ff0000" if int(status) >= 400 else "#ffffff"
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

