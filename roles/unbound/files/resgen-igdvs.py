import re

# Note: all straight up domain blocking has been moved to unbound blocked-sites
# list, much faster than using this script. Using this only for stuff that
# requires regular expressions.

blocked_google = ('mail.google', 'plus.google', 'translate.google', 'inbox.google')
blocked_domain_strings = ('yahoo', 'pinterest', 'hoxxproxytest', 'youtube', 'playboy')

def is_blocked_domain(qdn):
  gimage = re.compile('encrypted[-]tbn[01234567][.]gstatic[.]com')

  return (qdn.startswith(blocked_google) or
          any(d for d in blocked_domain_strings if d in qdn) or
          gimage.search(qdn) <> None)

# allow the library 17.x machines to access youtube
def is_17_youtube(qdn, ip):
  if ((qdn.endswith('youtube.com.') or
      qdn.endswith('googlevideo.com.')) and
      ip in ('10.11.17.1','10.11.17.2')):
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
      if not msg.set_return_msg(qstate):
        qstate.ext_state[id] = MODULE_ERROR
        return True

      #we don't need validation, result is valid
      qstate.return_msg.rep.security = 2
      qstate.ext_state[id] = MODULE_FINISHED
      qstate.return_rcode = RCODE_NXDOMAIN
      return True
    elif '.google.' in qdn:
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
