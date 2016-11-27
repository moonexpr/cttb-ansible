import re

domain_name = 'sipx.cttbpbx01.net.'
blocked_domains = ('renren.com.','anime1.com.', 'gmail.com.', 'twitter.com.', 'meebo.com.', 'facebook.com.', 'imgur.com.', 'youtube.com.', 'scribd.com.', 'archive.org.', 'mail.google.com.'+ domain_name, 'mail.google.com.', 'plus.google.com.'+ domain_name, 'plus.google.com.', 'translate.google.com.'+ domain_name, 'translate.google.com.', '4everproxy.com.', '500px.com.', 'aniscartujo.com.', 'anonymizer.com.', 'anonymous-proxy-servers.net.', 'artdoxa.com.', 'barracuda.com.', 'best-proxy.com.ca.', 'bypassthat.com.', 'chatterbate.com.', 'cruisenude.com.', 'cyberghostvpn.com.', 'digilet.org.', 'duckduckgo.com.', 'faceofliberty.com.', 'fastproxy.link.', 'filterbypass.me.', 'fuckbook.com.', 'getfoxyproxy.org.', 'hidemyass.com.', 'instagram.com.', 'ipredator.se.', 'ispblocked.com.', 'istlsfastyet.com.', 'ixquick.com.', 'kproxy.com.', 'lushstories.com.', 'megaproxy.com.', 'megaproxy.pl.', 'mitmproxy.org.', 'mousematrix.com.', 'myhttpsproxy.com.', 'mysslproxy.com.', 'nordvpn.com.', 'online-convert.com.', 'onlinevideoconverter.com.', 'openvpn.net.', 'pandashield.com.', 'proxfree.com.', 'proximize.me.', 'proxpn.com.', 'proxy-service.de.', 'proxyone.net.', 'proxysite.com.', 'proxyssl.com.', 'reddit.com.', 'rrpproxy.net.', 'penthouse.com.', 'siteenable.com.', 'sslproxybrowser.com.', 'sslproxyfree.com.', 'sslproxyunblocker.com.', 'ssltunnel.net.', 'sslunblock.net.', 'sslunblocker.com.', 'sslvideoproxy.com.', 'stunnel.org.', 'surfwecan.net.', 'thenude.eu.', 'thepiratebay-proxylist.org.', 'theproxy.ca.', 'toplessvegasonline.com.', 'torrentfreak.com.', 'torrentz-proxy.com.', 'torrentz.eu.', 'unblock-proxy.com.', 'unblockstardoll.com.', 'unblockvideos.com.', 'videoproxyunblocker.com.', 'vidproxy.com.', 'vpnbook.com.', 'vpndeluxe.com.', 'yande.re.', 'yandex.com.', 'zivity.com.', 'privatelee.com.', '12345proxy.pk.', 'vimeo.com.', 'moatads.com.', 'adnxs.com.', 'pix.btrll.com.')

def is_blocked_domain(qdn):
  gotmail = re.compile('mail')
  isdrba  = re.compile('drba')
  yahoo = re.compile('yahoo')
  bing = re.compile ('bing.com')
  pinterest = re.compile('pinterest')
  b07 = gotmail.search(qdn) <> None and isdrba.search(qdn) == None
  b08 = yahoo.search(qdn) <> None
  b09 = bing.search(qdn) <> None
  b10 = pinterest.search(qdn) <> None

  gimage = re.compile('encrypted[-]tbn[01234567][.]gstatic[.]com')
  b21 = gimage.search(qdn) <> None

  return qdn.endswith(blocked_domains) or b07 or b08 or b09 or b10 or b21

# allow the library 17.x machines to access youtube
def is_17_youtube(qdn, ip):
  if (qdn.endswith('youtube.com.') or qdn.endswith('googlevideo.com.')) and ip in ('10.11.17.1','10.11.17.2'):
    return True
  else:
    return False

def init(id, cfg): return True

def deinit(id): return True

def inform_super(id, qstate, superqstate, qdata): return True

def operate(id, event, qstate, qdata):
  src_ip = ''

  if (event == MODULE_EVENT_NEW) or (event == MODULE_EVENT_PASS):
    qdn = qstate.qinfo.qname_str

    # finds the source ip
    rl = qstate.mesh_info.reply_list
    while (rl):
      if rl.query_reply:
        q = rl.query_reply
        src_ip = q.addr
	break

    if is_17_youtube(qdn, src_ip):
      qstate.ext_state[id] = MODULE_WAIT_MODULE
      return True
    elif is_blocked_domain(qdn):
      msg = DNSMessage(qdn, RR_TYPE_A, RR_CLASS_IN, PKT_QR | PKT_RA | PKT_AA)
      msg.answer.append('%s 3600 IN A 127.0.0.2' % qdn)
      if not msg.set_return_msg(qstate):
        qstate.ext_state[id] = MODULE_ERROR
        return True

      #we don't need validation, result is valid
      qstate.return_msg.rep.security = 2
      qstate.ext_state[id] = MODULE_FINISHED
      qstate.return_rcode = RCODE_NOERROR
      return True
    elif re.search('.google.',qdn) <> None:
      msg = DNSMessage(qdn, RR_TYPE_A, RR_CLASS_IN, PKT_QR | PKT_RA | PKT_AA)
      msg.answer.append('%s 3600 IN CNAME nosslsearch.google.com.' % qdn)
      msg.answer.append('nosslsearch.google.com. 86400 IN A 216.239.32.20')
      if not msg.set_return_msg(qstate):
        qstate.ext_state[id] = MODULE_ERROR
        return True

      #we don't need validation, result is valid
      qstate.return_msg.rep.security = 2
      qstate.ext_state[id] = MODULE_FINISHED
      qstate.return_rcode = RCODE_NOERROR
      return True
    else:
      #pass the query to validator
      qstate.ext_state[id] = MODULE_WAIT_MODULE
      return True

  if event == MODULE_EVENT_MODDONE:
    qstate.ext_state[id] = MODULE_FINISHED
    return True

  log_err("pythonmod: bad event")
  qstate.ext_state[id] = MODULE_ERROR
  return True
