"""
app: Datadog Monitor
author: Your Name
summary: Displays Datadog trace stats
desc: Shows recent request statuses and a 24-hour summary of successful/failed requests from a Datadog trace search. Requires a companion Cloudflare Worker.
schema: get_schema
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
        return render.Error("HTTP Error %d" % rep.status_code)

    raw_body = rep.body()
    if not raw_body.startswith("{") or not raw_body.endswith("}"):
        return render.Root(child = render.Text("Invalid JSON"))

    now = time.now()
    minute = now.minute

    if raw_body.startswith("{") and raw_body.endswith("}"):
        data = json.decode(raw_body)
    else:
        return render.Error("Invalid JSON format")
        
    if not data.get("summary"):
        return render.Error("Missing 'summary' in response")
        
    # Determine which widget to display
    child_widget = render_summary(data)

    # Return the final, single Root object
    return render.Root(
        child = child_widget,
    )

def render_summary(data):
    """Renders the 24-hour summary view."""
    summary = data.get("summary")
    timestamp = data.get("timestamp")

    if not summary:
        return render.Text("Summary data not available.")

    reset = summary.get("reset", {})
    transfer = summary.get("transfer", {})

    # Format the timestamp for display
    updated_at = ""
    if timestamp:
        t = time.parse_time(timestamp)
        updated_at = "Upd: %02d:%02d" % (t.hour, t.minute)

    # Use a Column with a fixed top spacer to manually position the content.
    # This is the most compatible layout method.
    return render.Stack(
        render.Column(
            main_align = "space_evenly",  # this controls position of children, start = top
            expanded = True,
            cross_align = "center",
            children = [
                render.Row(
                    expanded = True,
                    main_align = "left",
                    children = [
                        render.Text("Reset:  ", font="tom-thumb"),
                        render.Text(str(reset.get("success", 0)), color = "#06402b", font="tom-thumb"),
                        render.Text("/", font="tom-thumb"),
                        render.Text(str(reset.get("fourHundred", 0)), color = "#ffee8c", font="tom-thumb"),
                        render.Text("/", font="tom-thumb"),
                        render.Text(str(reset.get("fiveHundred", 0)), color = "#8b0000", font="tom-thumb"),
                    ],
                ),
                render.Row(
                    expanded = True,
                    main_align = "left",
                    children = [
                        render.Text("Transfer:  ", font="tom-thumb"),
                        render.Text(str(transfer.get("success", 0)), color = "#06402b", font="tom-thumb"),
                        render.Text("/", font="tom-thumb"),
                        render.Text(str(transfer.get("fourHundred", 0)), color = "#ffee8c", font="tom-thumb"),
                        render.Text("/", font="tom-thumb"),
                        render.Text(str(transfer.get("fiveHundred", 0)), color = "#8b0000", font="tom-thumb"),
                    ],
                ),
            ],
        )
    )

