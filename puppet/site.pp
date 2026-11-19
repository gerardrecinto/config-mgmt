$src         = lookup('allow_source')
$api_port    = lookup('api_port')
$admin_port  = lookup('admin_port')
$app_version = lookup('app_version')
$allow_ports = lookup('allow_tcp_ports')

Exec { path => ['/usr/sbin', '/usr/bin', '/sbin', '/bin'] }

package { ['nginx-light', 'iptables']: ensure => installed }

file { '/etc/nginx/sites-enabled/default':
  ensure  => absent,
  require => Package['nginx-light'],
  notify  => Service['nginx'],
}

file { '/etc/nginx/conf.d/api.conf':
  ensure  => file,
  mode    => '0644',
  content => epp('/lab/puppet/api.conf.epp', {
    'api_port'    => $api_port,
    'admin_port'  => $admin_port,
    'app_version' => $app_version,
  }),
  require => Package['nginx-light'],
  notify  => Service['nginx'],
}

service { 'nginx':
  ensure   => running,
  provider => 'base',
  start    => '/etc/init.d/nginx start',
  stop     => '/etc/init.d/nginx stop',
  status   => '/etc/init.d/nginx status',
  restart  => '/etc/init.d/nginx reload',
}

# Firewall: allow rules first, default DROP last, each rule checked with -C so a rerun changes nothing.
$est = '-m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT'
exec { 'fw-established':
  command => "iptables -A INPUT ${est}",
  unless  => "iptables -C INPUT ${est}",
  require => Package['iptables'],
  before  => Exec['fw-default-drop'],
}
exec { 'fw-loopback':
  command => 'iptables -A INPUT -i lo -j ACCEPT',
  unless  => 'iptables -C INPUT -i lo -j ACCEPT',
  require => Package['iptables'],
  before  => Exec['fw-default-drop'],
}
$allow_ports.each |$p| {
  $rule = "-s ${src} -p tcp -m tcp --dport ${p} -j ACCEPT"
  exec { "fw-allow-${p}":
    command => "iptables -A INPUT ${rule}",
    unless  => "iptables -C INPUT ${rule}",
    require => Package['iptables'],
    before  => Exec['fw-default-drop'],
  }
}
exec { 'fw-default-drop':
  command => 'iptables -P INPUT DROP',
  unless  => 'iptables -S INPUT | grep -qx -- "-P INPUT DROP"',
}
