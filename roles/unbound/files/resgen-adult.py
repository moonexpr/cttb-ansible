import re

blocked_domain_strings = ('hoxxproxytest', 'playboy')
google_no_sslsearch = (
        'accounts',
        'alt',
        'android',
        'apis',
        'calendar',
        'chatenabled',
        'client',
        'dl',
        'docs',
        'drive',
        'fonts',
        'gmail-imap',
        'hangouts',
        'history',
        'id',
        'inputtools',
        'mail',
        'maps',
        'mtalk',
        'news',
        'nosslsearch',
        'notifications',
        'picasaweb',
        'pki',
        'play',
        'plus',
        'safebrowsing',
        'security',
        'support',
        'talk',
        'tools') 

def init(id, cfg): return True

def deinit(id): return True

def inform_super(id, qstate, superqstate, qdata): return True

def operate(id, event, qstate, qdata):
  if (event == MODULE_EVENT_NEW) or (event == MODULE_EVENT_PASS):
    src_ip = ''
    qdn = qstate.qinfo.qname_str

    # finds the source ip
    rl = qstate.mesh_info.reply_list
    while (rl):
      if rl.query_reply:
        q = rl.query_reply
        src_ip = q.addr
        break

    if any(d for d in blocked_domain_strings if d in qdn):
      msg = DNSMessage(qdn, RR_TYPE_A, RR_CLASS_IN, PKT_QR | PKT_RA | PKT_AA)
      if not msg.set_return_msg(qstate):
        qstate.ext_state[id] = MODULE_ERROR
        return True

      #we don't need validation, result is valid
      qstate.return_msg.rep.security = 2
      qstate.ext_state[id] = MODULE_FINISHED
      qstate.return_rcode = RCODE_NXDOMAIN
      return True
    elif ('.google.' in qdn and
        not qdn.startswith(google_no_sslsearch) and
        (
            (qstate.qinfo.qtype == RR_TYPE_A) or
            (qstate.qinfo.qtype == RR_TYPE_ANY)
         )):

      #create instance of DNS message (packet) with given parameters
      msg = DNSMessage(qdn, RR_TYPE_A, RR_CLASS_IN, PKT_QR | PKT_RA | PKT_AA)
      #append RR
      msg.answer.append('%s 3600 IN CNAME nosslsearch.google.com.' % qdn)
      msg.answer.append('nosslsearch.google.com. 86400 IN A 216.239.32.20')

      if not msg.set_return_msg(qstate):
        qstate.ext_state[id] = MODULE_ERROR
        return True

      #we don't need validation, result is valid
      qstate.return_msg.rep.security = 2

      qstate.return_rcode = RCODE_NOERROR
      qstate.ext_state[id] = MODULE_FINISHED
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
