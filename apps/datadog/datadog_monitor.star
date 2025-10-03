"""
app: Datadog Monitor
author: Your Name
summary: Displays Datadog trace stats
desc: Shows recent request statuses and a 24-hour summary of successful/failed requests from a Datadog trace search. Requires a companion Cloudflare Worker.
"""

load("render.star", "render")
load("http.star", "http")
load("encoding/json.star", "json")
load("time.star", "time")

def main(config):
    """App entrypoint."""
    # --- CONFIGURATION WORKAROUND ---
    # INSTRUCTIONS: Replace the placeholder values below with your
    # actual Worker URL and Auth Token.
    # WARNING: This is less secure as your token will be stored
    # in plaintext in your apps repository.
    worker_url = "https://your-worker-url.workers.dev"
    auth_token = "your_secret_auth_token"

    # Display a message if the default values haven't been changed.
    if "your-worker-url" in worker_url or "your_secret_auth_token" in auth_token:
        return render.Root(
            child = render.Text("Configure app in .star file"),
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

