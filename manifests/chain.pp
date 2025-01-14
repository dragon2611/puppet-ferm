# @summary This defined resource manages ferm/iptables chains
#
# @example create a custom chain, e.g. for all incoming SSH connections
#   ferm::chain{'check-ssh':
#     chain               => 'SSH',
#     disable_conntrack   => true,
#     log_dropped_packets => true,
#   }
#
# @param disable_conntrack Disable/Enable usage of conntrack
# @param log_dropped_packets Enable/Disable logging of packets to the kernel log, if no explicit chain matched
# @param policy Set the default policy for CHAIN (works only for builtin chains)
#   Default value: undef
#   Allowed values: (ACCEPT|DROP) (see Ferm::Policies type)
# @param chain Name of the chain that should be managed
#   Default value: $name (resource name)
#   Allowed values: String[1]
# @param table Select the target table (filter/raw/mangle/nat)
#   Default value: 'filter'
#   Allowed values: (filter|raw|mangle|nat) (see Ferm::Tables type)
# @param ip_versions Set list of versions of ip we want ot use.
#   Default value: $ferm::ip_versions
define ferm::chain (
  Boolean $disable_conntrack,
  Boolean $log_dropped_packets,
  String[1] $chain                     = $name,
  Optional[Ferm::Policies] $policy     = undef,
  Ferm::Tables $table                  = 'filter',
  Array[Enum['ip','ip6']] $ip_versions = $ferm::ip_versions,
) {
  # prevent unmanaged files due to new naming schema
  # keep the default "filter" chains in the original location
  # only prefix chains in other tables with the table name
  if $table == 'filter' and $chain in ['INPUT', 'FORWARD', 'OUTPUT'] {
    $filename = "${ferm::configdirectory}/chains/${chain}.conf"
  } else {
    $filename = "${ferm::configdirectory}/chains/${table}-${chain}.conf"
  }

  $builtin_chains = {
    'raw'    => ['PREROUTING', 'OUTPUT'],
    'nat'    => ['PREROUTING', 'INPUT', 'OUTPUT', 'POSTROUTING'],
    'mangle' => ['PREROUTING', 'INPUT', 'FORWARD', 'OUTPUT', 'POSTROUTING'],
    'filter' => ['INPUT', 'FORWARD', 'OUTPUT'],
  }

  if $policy and ! ($chain in $builtin_chains[$table]) {
    fail("Can only set a default policy for builtin chains. '${chain}' is not a builtin chain.")
  }

  # concat resource for the chain
  concat{$filename:
    ensure  => 'present',
  }

  concat::fragment{"${table}-${chain}-policy":
    target  => $filename,
    content => epp(
      "${module_name}/ferm_chain_header.conf.epp", {
        'policy'            => $policy,
        'disable_conntrack' => $disable_conntrack,
      }
    ),
    order   => '01',
  }

  if $log_dropped_packets {
    concat::fragment{"${table}-${chain}-footer":
      target  => $filename,
      content => epp("${module_name}/ferm_chain_footer.conf.epp", { 'chain' => $chain }),
      order   => 'zzzzzzzzzzzzzzzzzzzzz',
    }
  }

  # make sure the generated snippet is actually included
  concat::fragment{"${table}-${chain}-config-include":
    target  => $ferm::configfile,
    content => epp(
      "${module_name}/ferm-table-chain-config-include.epp", {
        'ip'       => join($ip_versions, ' '),
        'table'    => $table,
        'chain'    => $chain,
        'filename' => $filename,
      }
    ),
    order   => "${table}-${chain}",
    require => Concat[$filename],
  }
}
