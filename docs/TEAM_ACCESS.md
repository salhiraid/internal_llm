# Team Access

Server role:

- DNS server: `192.168.0.32`
- LLM URL: `https://llm.internal.local`
- Grafana URL: `https://grafana.internal.local`
- Prometheus local URL on server: `http://127.0.0.1:9090`

## Team browser setup

1. Set the DNS server on each team machine, or on your router, to `192.168.0.32`.
2. Install the mkcert root CA from the live server path:
   `/Users/raid/internal-llm/certs/rootCA.pem`
3. Open `https://llm.internal.local`.
4. Team members can sign up. New accounts can remain pending until the admin approves them in Open WebUI.

## Admin access

- Open WebUI admin email: `admin@company.local`
- Open WebUI admin password: stored in the live `.env`
- Grafana admin user: `admin`
- Grafana admin password: stored in the live `.env`

Do not commit real passwords into git.
