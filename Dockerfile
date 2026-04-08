FROM netboxcommunity/netbox:latest

COPY plugin_requirements.txt /opt/netbox/

RUN pip install -r /opt/netbox/plugin_requirements.txt

COPY netbox/plugins.py /etc/netbox/config/plugins.py

RUN SECRET_KEY="dummykeydummykeydummykeydummykey" \
    /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py collectstatic --no-input