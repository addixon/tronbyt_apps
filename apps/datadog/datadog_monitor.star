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
        ],
    )

def main(config):
    """App entrypoint."""
    worker_url = config.get("worker_url")
    auth_token = config.get("auth_token")

    if not worker_url or not auth_token:
        return render.Root(
            child = render.Text("Missing Config"),
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
            child = render.Column(
                children=[
                    render.Text("HTTP Error:"),
                    render.Text(str(rep.status_code)),
                ]
            ),
        )

    raw_body = rep.body()
    if not raw_body.startswith("{") or not raw_body.endswith("}"):
        return render.Root(child = render.Text("Invalid JSON"))

    data = json.decode(raw_body)
    now = time.now()
    minute = now.minute

    # For now, we will always show the summary view for diagnostics
    child_widget = render_summary(data)

    # Return the final, single Root object
    return render.Root(
        child = child_widget,
    )

def render_summary(data):
    """DIAGNOSTIC: Renders a step-by-step check of the data."""
    
    # Step 1: Check if the 'summary' key exists
    summary = data.get("summary")
    if not summary:
        return render.Text("Debug: No 'summary' key in JSON.")

    # Step 2: Check if the 'reset' key exists within summary
    reset = summary.get("reset")
    if not reset:
        return render.Text("Debug: No 'reset' key in summary.")

    # Step 3: Check if the 'success' key exists within reset
    success_count = reset.get("success")
    if success_count == None: # Must check for None, as 0 is a valid value
        return render.Text("Debug: No 'success' key in reset.")

    # If all checks pass, the data structure is correct.
    # The original rendering code can be restored.
    return render.Column(
        children = [
            render.Text("Debug OK!"),
            render.Text("Success: " + str(success_count)),
            render.Text("Type: " + str(type(success_count))),
        ],
    )


# --- Original Rendering Functions (for reference) ---

def render_recent_requests(requests):
    """Renders the scrolling marquee view."""
    if not requests:
        return render.Text("No requests in last 15m")

    children = []
    for req in requests:
        req_type = "RST" if "reset" in req.get("resource_name", "") else "XFR"
        status = req.get("status_code", "???")
        color = "#ff0000" if int(str(status)) >= 400 else "#ffffff"
        children.append(
            render.Text("%s:%s" % (req_type, status), color = color),
        )

    return render.Marquee(
        width = 64,
        child = render.Row(
            main_align = "space_around",
            expanded = True,
            children = children,
        ),
    )

def original_render_summary(data):
    """Renders the 24-hour summary view."""
    summary = data.get("summary")
    timestamp = data.get("timestamp")

    if not summary:
        return render.Text("Summary data not available.")

    reset = summary.get("reset", {})
    xfer = summary.get("transfer", {})

    updated_at = ""
    if timestamp:
        t = time.parse_time(timestamp)
        updated_at = "Upd: %02d:%02d" % (t.hour, t.minute)

    return render.Column(
        children = [
            render.Row(
                children = [
                    render.Text("Reset: "),
                    render.Text(str(reset.get("success", 0)), color = "#00ff00"),
                    render.Text("/"),
                    render.Text(str(reset.get("fail", 0)), color = "#ff0000"),
                    render.Box(width=2),
                    render.Text(updated_at, font="tom-thumb"),
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
    )

