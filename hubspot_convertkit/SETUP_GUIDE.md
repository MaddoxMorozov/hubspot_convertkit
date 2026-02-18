# HubSpot to Kit - Weekly Sync Workflow Setup Guide

## Workflow Overview

This workflow runs every week (Monday 2AM) and syncs new HubSpot contacts to Kit (ConvertKit) as subscribers. It pulls contacts created since the last sync, maps their fields, and upserts them into Kit via the v4 API.

### Flow Diagram

```
Weekly Schedule (every Monday 2AM)
    |
    v
Get Last Sync Timestamp (reads from persistent static data)
    |
    v
Search HubSpot Contacts (POST /crm/v3/objects/contacts/search)
    |
    v
Handle Pagination (accumulates results across pages)
    |
    v
More Pages? ----yes----> loops back to Search HubSpot Contacts
    |no
    v
Map Contact Fields (transforms HubSpot to Kit schema)
    |
    v
Has Email?
    |yes                |no
    v                   v
Loop Over Items     No Email - Skip
    |loop
    v
Create Subscriber in Kit (POST /v4/subscribers - upsert)
    |
    v
Wait (0.5s rate limit)
    |
    loops back to Loop Over Items
    |done
    v
Save Sync Timestamp (persists for next run)
```

### Contact Fields Synced

| HubSpot Property          | Kit Field             | Type        |
|---------------------------|-----------------------|-------------|
| `email`                   | `email_address`       | Required    |
| `firstname`               | `first_name`          | Top-level   |
| `product_list`            | `Product List`        | Custom      |
| `lifecyclestage`          | `Lifecycle Stage`     | Custom      |
| `hs_lead_status`          | `Lead Status`         | Custom      |
| `website`                 | `Website`             | Custom      |
| `dr_code`                 | `DR Code`             | Custom      |
| `hs_country_region_code`  | `Country Region Code` | Custom      |
| `city`                    | `City`                | Custom      |
| `jf_usercat`              | `JF UserCat`          | Custom      |
| `ist_lead_source`         | `IST Lead Source`     | Custom      |

---

## Prerequisites

1. **Render account** at [render.com](https://render.com)
2. **HubSpot account** with OAuth2 app configured
3. **Kit (ConvertKit) account** with v4 API access

---

## Deploy n8n on Render

### Option A: One-Click Blueprint Deploy (Recommended)

1. Push this repo to GitHub
2. Go to [Render Dashboard](https://dashboard.render.com/) > **Blueprints** > **New Blueprint Instance**
3. Connect your GitHub repo containing this project
4. Render will detect `render.yaml` and create:
   - A **Web Service** running n8n (Docker)
   - A **PostgreSQL database** for workflow storage
   - A **Persistent Disk** for n8n data
5. Set these values when prompted:
   - `N8N_BASIC_AUTH_USER` — your login username
   - `N8N_BASIC_AUTH_PASSWORD` — a strong password
6. Click **Apply** and wait for deployment (~3-5 minutes)
7. Access n8n at `https://n8n-xxxx.onrender.com`

### Option B: Manual Deploy

1. Go to **Render Dashboard** > **New** > **Web Service**
2. Connect your GitHub repo
3. Set **Runtime** to **Docker**
4. Set **Port** to `5678`
5. Add environment variables from `.env.example`
6. Add a **Disk** at mount path `/home/node/.n8n` (1 GB)
7. Optionally create a PostgreSQL database and link it

### After Deployment

- Set `WEBHOOK_URL` to your full Render URL (e.g., `https://n8n-xxxx.onrender.com/`)
- **Important**: Free tier instances spin down after inactivity — scheduled workflows won't fire. Use a paid plan for reliable weekly syncs.

---

## Import & Configure the Workflow

### 1. Import the Workflow

1. Open your n8n instance
2. Go to **Workflows** > **Add Workflow** > **Import from File**
3. Select `hubspot_to_convertkit_workflow.json`

### 2. Configure HubSpot Credentials

This workflow uses HubSpot OAuth2 for the Search API (no webhook needed).

1. In n8n, go to **Credentials** > **Add Credential** > **HubSpot OAuth2 API**
2. Enter your **Client ID** and **Client Secret**
3. Complete the OAuth2 authorization flow
4. Required scope: `crm.objects.contacts.read`
5. Update the **Search HubSpot Contacts** node to use your credential

### 3. Configure Kit (ConvertKit) v4 API

#### Get your v4 API Key

**Important**: This workflow uses the Kit v4 API, which requires a v4 API key (not the v3 key).

1. Log into [Kit](https://app.kit.com/)
2. Go to **Settings** > **Developer** > **API keys**
3. Generate a new v4 API key
4. Copy the key

#### Update the Workflow

In the **Create Subscriber in Kit** node, replace `YOUR_KIT_V4_API_KEY` with your actual v4 API key in the header parameters.

### 4. Create Custom Fields in Kit

Before running the workflow, create these custom fields in Kit:

1. Go to **Subscribers** > **Custom Fields**
2. Add the following fields (names must match exactly):
   - `Product List`
   - `Lifecycle Stage`
   - `Lead Status`
   - `Website`
   - `DR Code`
   - `Country Region Code`
   - `City`
   - `JF UserCat`
   - `IST Lead Source`

> Note: `first_name` is a default field in Kit and does not need to be created.

### 5. Verify HubSpot Custom Properties

Ensure these custom properties exist in HubSpot (these are internal API names):
- `product_list`
- `dr_code`
- `jf_usercat`
- `ist_lead_source`

Standard properties (`lifecyclestage`, `hs_lead_status`, `website`, `hs_country_region_code`, `city`) should already exist.

### 6. Activate the Workflow

1. Review all nodes and ensure credentials are connected
2. Click **Save**
3. Toggle the workflow to **Active**
4. The schedule trigger will fire every Monday at 2AM

---

## Testing

1. Run the workflow manually using **Test Workflow** in n8n
2. Check the **Executions** panel to see results at each node
3. Verify contacts appear in Kit under **Subscribers** with custom fields populated
4. On first run, it syncs contacts created in the last 7 days

---

## How It Works

### Weekly Scheduling
The workflow uses a Schedule Trigger that fires every Monday at 2:00 AM. You can change the day/time in the node settings.

### State Tracking
The workflow persists the last sync timestamp using n8n's `$getWorkflowStaticData('global')`. On first run, it defaults to 7 days ago. Each successful run saves the current timestamp so the next run picks up where it left off.

### Pagination
HubSpot's Search API returns max 100 results per page. The workflow loops through all pages automatically, accumulating contacts before processing them. This handles any volume of contacts.

### Idempotency
Kit's `POST /v4/subscribers` is an upsert -- if the email already exists, it updates the subscriber. Running the workflow multiple times for the same contacts won't create duplicates.

### Error Handling
- The Kit subscriber node has retry-on-fail (3 attempts, 1s backoff)
- Continue-on-error is enabled so a single bad email won't stop the batch
- If the workflow fails mid-run, the timestamp is NOT updated, so the next run re-fetches the same contacts (safe due to upsert)

---

## Troubleshooting

### No contacts synced
- Check that contacts were created in HubSpot after the last sync timestamp
- Verify the HubSpot OAuth2 credential is valid and has `crm.objects.contacts.read` scope
- Run manually and check the output of each node

### Kit API errors
- `401` - Invalid or expired v4 API key (make sure it's a v4 key, not v3)
- `422` - Invalid email format or missing required fields
- `429` - Rate limit hit (the Wait node should prevent this, increase delay if needed)

### Custom fields not appearing in Kit
- Field names must match exactly (case-sensitive): `Product List`, `DR Code`, etc.
- Create all custom fields in Kit before the first sync

### HubSpot custom properties empty
- Verify the internal API names: `product_list`, `dr_code`, `jf_usercat`, `ist_lead_source`
- These must be created as contact properties in HubSpot Settings > Properties

---

## Customization

### Change sync frequency
Edit the **Weekly Schedule** node to change the interval (daily, every 2 weeks, etc.).

### Add more HubSpot fields
1. Add the property name to the `properties` array in the **Search HubSpot Contacts** JSON body
2. Add the mapping in the **Map Contact Fields** code node
3. Add the field to the `fields` object in the **Create Subscriber in Kit** JSON body
4. Create the corresponding custom field in Kit

### Reset sync (re-sync all contacts)
Delete the workflow's static data in n8n (Settings > Static Data) to force a full re-sync from the last 7 days.

---

## Security Notes

- **Never commit API keys or secrets to Git.** Use n8n's built-in Credentials system or environment variables.
- The Kit v4 API key is stored in the HTTP request header. For production, consider storing it in n8n's **Credentials** system.
- HubSpot credentials use OAuth2 which is managed by n8n's credential system.
- `creds.txt` is excluded via `.gitignore` — never track credential files in version control.
- The `N8N_ENCRYPTION_KEY` is auto-generated by Render and encrypts stored credentials at rest.
