plugin/k8s_external
<!--
When reporting bugs and requesting assistance, please include:
* the version of CoreDNS you are using
* your Corefile
* logs, if applicable

Thanks for using CoreDNS!
-->
using coredns 1.3.1 and the k8s_external plugin i miss some A records in the dns subzone

<pre>
.:53 {
    errors
    health
    kubernetes k8s.cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       upstream
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    k8s_external k9s.cluster.local in-addr.arpa ip6.arpa {
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf
    cache 30
    loop
    reload
    loadbalance
}
</pre>

the documentation notes that there is a stub/apex zone. But i'm missing an NS record and an A record
<pre>
dig NS k9s.cluster.local => invalid dns package
dig NS dns.k9s.cluster.local =>  no entry
dig A ns1.dns.k9s.cluster.local => no entry
</pre>

The kubernetes plugin handles them like
<pre>
dig NS k8s.cluster.local => ns.dns.k8s.cluster.local.
dig NS dns.k8s.cluster.local => no entry
dig A ns.dns.k8s.cluster.local => 10.96.x.y
</pre>

### Additional contract requirements

- A query for the apex NS record must also return the nameserver's A record in the Additional section, named after the nameserver (`ns1.dns.<zone>`, e.g. `ns1.dns.k9s.cluster.local`).
