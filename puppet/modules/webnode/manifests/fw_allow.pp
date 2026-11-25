# Allow one TCP port from one source range. Idempotent: the rule is added only if iptables -C says it is missing.
define webnode::fw_allow (
  String[1] $source,
  Integer[1, 65535] $port,
) {
  $rule = "-s ${source} -p tcp -m tcp --dport ${port} -j ACCEPT"

  exec { "fw-allow-${port}":
    command => "iptables -A INPUT ${rule}",
    unless  => "iptables -C INPUT ${rule}",
    require => Package['iptables'],
    before  => Exec['fw-default-drop'],
  }
}
