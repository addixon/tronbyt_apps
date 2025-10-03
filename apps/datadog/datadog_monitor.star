/**
 * Welcome to Cloudflare Workers! This is your first worker.
 *
 * - Run `npm run dev` in your terminal to start a development server
 * - Open a browser tab at http://localhost:8787/ to see your worker in action
 * - Run `npm run deploy` to publish your worker
 *
 * Learn more at https://developers.cloudflare.com/workers/
 */

export interface Env {
	DD_API_KEY: string;
	DD_APP_KEY: string;
	DD_SITE: string;
	AUTH_TOKEN: string;
}

// Main handler for the Worker
export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		// 1. Authentication
		const authHeader = request.headers.get('Authorization');
		if (!authHeader || authHeader !== `Bearer ${env.AUTH_TOKEN}`) {
			return new Response('Unauthorized', { status: 401 });
		}

		try {
			// 2. Fetch data from Datadog
			const summary = await getSummaryData(env);
			const recent_requests = await getRecentTraces(env);
			const timestamp = new Date().toISOString();

			// 3. Construct the JSON response
			const responseData = {
				summary,
				recent_requests,
				timestamp,
			};

			return new Response(JSON.stringify(responseData), {
				headers: { 'Content-Type': 'application/json' },
			});

		} catch (error) {
			console.error('Error in worker:', error);
			const errorMessage = error instanceof Error ? error.message : 'An unknown error occurred';
			return new Response(JSON.stringify({ error: errorMessage }), {
				status: 500,
				headers: { 'Content-Type': 'application/json' },
			});
		}
	},
};


/**
 * Fetches individual trace events from the last 15 minutes.
 */
async function getRecentTraces(env: Env): Promise<any[]> {
	const now = new Date();
	const fifteenMinutesAgo = new Date(now.getTime() - 15 * 60 * 1000);
	// CORRECTED: More specific query targeting resource_name
	const query = "service:assets-domain @span.kind:server resource_name:(*reset* OR *transfer*)";

	const url = `https://api.${env.DD_SITE}/api/v2/logs/events/search`;
	const requestBody = {
		filter: { from: fifteenMinutesAgo.toISOString(), to: now.toISOString(), query: query },
		sort: "-timestamp",
        page: { limit: 25 }, // Limit to a reasonable number for display
	};
	const headers = {
		'Content-Type': 'application/json',
		'DD-API-KEY': env.DD_API_KEY,
		'DD-APPLICATION-KEY': env.DD_APP_KEY,
	};

	const response = await fetch(url, { method: 'POST', headers: headers, body: JSON.stringify(requestBody) });

	if (!response.ok) {
		const errorBody = await response.text();
		console.error(`Datadog Events API Error (${response.status}):`, errorBody);
		throw new Error(`Datadog Events API request failed: ${response.statusText}`);
	}
	const body = (await response.json()) as any;
	return (body.data || []).map((d: any) => d.attributes);
}


/**
 * Fetches aggregate counts over the last 24 hours.
 */
async function getSummaryData(env: Env): Promise<{ reset: { success: number; fail: number; }; transfer: { success: number; fail: number; }; }> {
	const apiUrl = `https://api.${env.DD_SITE}/api/v2/logs/analytics/aggregate`;
	// CORRECTED: More specific query targeting resource_name
	const query = "service:assets-domain @span.kind:server resource_name:(*reset* OR *transfer*)";

	const requestBody = {
		filter: {
			from: "now-24h",
			to: "now",
			query: query,
		},
		group_by: [
			{ facet: "resource_name", limit: 10, sort: { order: "desc" } },
			{ facet: "http.status_code", limit: 10, sort: { order: "desc" } },
		],
	};
    const headers = {
        'Content-Type': 'application/json',
        'DD-API-KEY': env.DD_API_KEY,
        'DD-APPLICATION-KEY': env.DD_APP_KEY,
    };

	const response = await fetch(apiUrl, { method: 'POST', headers: headers, body: JSON.stringify(requestBody) });

	if (!response.ok) {
		const errorBody = await response.text();
		console.error(`Datadog Aggregate API Error (${response.status}):`, errorBody);
		throw new Error(`Datadog Aggregate API request failed: ${response.statusText}`);
	}
	const body = (await response.json()) as any;
	const buckets = body.data?.buckets || [];

	const summary = {
		reset: { success: 0, fail: 0 },
		transfer: { success: 0, fail: 0 },
	};

	for (const bucket of buckets) {
		const resourceName = bucket.by.resource_name || '';
		const statusCode = bucket.by['http.status_code'] || 0;
		const count = bucket.computes.count || 0;
		const isReset = resourceName.includes('reset');
		const isSuccess = statusCode < 400;

		if (isReset) {
			if (isSuccess) summary.reset.success += count;
			else summary.reset.fail += count;
		} else {
			if (isSuccess) summary.transfer.success += count;
			else summary.transfer.fail += count;
		}
	}
	return summary;
}

