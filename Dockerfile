FROM n8nio/n8n:latest

# Set working directory
WORKDIR /home/node

# Copy workflow files into the container for easy import
COPY hubspot_convertkit/hubspot_to_convertkit_workflow.json /home/node/workflows/
COPY hubspot_convertkit/HubSpot\ to\ ConvertKit\ -\ Sync\ New\ Contacts.json /home/node/workflows/

# n8n listens on port 5678 by default
EXPOSE 5678
