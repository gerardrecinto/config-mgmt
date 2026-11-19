{% import_yaml "desired-state.yaml" as d %}

packages:
  pkg.installed:
    - pkgs:
      - nginx-light
      - iptables

nginx-default-site-absent:
  file.absent:
    - name: /etc/nginx/sites-enabled/default
    - require:
      - pkg: packages

nginx-api-conf:
  file.managed:
    - name: /etc/nginx/conf.d/api.conf
    - source: salt://api.conf.jinja
    - template: jinja
    - mode: '0644'
    - context:
        d: {{ d | json }}
    - require:
      - pkg: packages

nginx-running:
  service.running:
    - name: nginx
    - reload: True
    - watch:
      - file: nginx-api-conf
      - file: nginx-default-site-absent

fw-established:
  iptables.append:
    - table: filter
    - chain: INPUT
    - match: conntrack
    - ctstate: ESTABLISHED,RELATED
    - jump: ACCEPT
    - require:
      - pkg: packages

fw-loopback:
  iptables.append:
    - table: filter
    - chain: INPUT
    - in-interface: lo
    - jump: ACCEPT
    - require:
      - pkg: packages

{% for p in d.allow_tcp_ports %}
fw-allow-{{ p }}:
  iptables.append:
    - table: filter
    - chain: INPUT
    - source: {{ d.allow_source }}
    - proto: tcp
    - dport: {{ p }}
    - jump: ACCEPT
    - require:
      - pkg: packages
{% endfor %}

fw-default-drop:
  iptables.set_policy:
    - table: filter
    - chain: INPUT
    - policy: DROP
    - require:
      - iptables: fw-established
      - iptables: fw-loopback
{% for p in d.allow_tcp_ports %}
      - iptables: fw-allow-{{ p }}
{% endfor %}
