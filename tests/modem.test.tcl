package require Tcl 8.6
package require tcltest
namespace import tcltest::*

# Add module dir to tm paths
set ThisScriptDir [file dirname [info script]]
set LibDir [file normalize [file join $ThisScriptDir .. lib]]

source [file join $ThisScriptDir "test_helpers.tcl"]
source [file join $ThisScriptDir "chatter.tcl"]
source [file join $LibDir "logger.tcl"]
source [file join $LibDir "phonebook.tcl"]
source [file join $LibDir "modem.tcl"]


test on-1 {Outputs OK message to local when an AT command is given} -setup {
  set config {
    inbound {
      ring_on_connect 0
      wait_for_ata 0
      auto_answer 0
      type rawtcpip
      speed 1200
    }
  }
  lassign [chatter::init] inRead outWrite
  set phonebook [Phonebook new]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript {
    {send "ATZ\r\n"}
    {expect "ATZ\r\n"}
    {expect "OK\r\n"}
    {send "ath\r\n"}
    {expect "ath\r\n"}
    {expect "OK\r\n"}
  }
} -body {
  $modem on
  chatter::chat $chatScript
} -cleanup {
  $modem off
  chatter::close
} -result {no errors}


test on-2 {Recognize +++ and escape to command mode for inbound connection} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 1
      type rawtcpip
      speed 1200
    }
  }
  set port [testHelpers::findUnusedPort]
  dict set config inbound port $port
  lassign [chatter::init] inRead outWrite
  set phonebook [Phonebook new]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript {
    {expect "RING\r\n"}
    {expect "CONNECT 1200\r\n"}
    {pause 1000}
    {send "+++"}
    {expect "+++"}
    {send "ath\r\n"}
    {expect "ath\r\n"}
    {expect "OK\r\n"}
    {expect "NO CARRIER\r\n"}
  }
} -body {
  $modem on
  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test on-3 {Ensure can resume a connect with ato from command mode} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 1
      type rawtcpip
      speed 1200
    }
  }
  set port [testHelpers::findUnusedPort]
  dict set config inbound port $port
  lassign [chatter::init] inRead outWrite
  set phonebook [Phonebook new]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript {
    {expect "RING\r\n"}
    {expect "CONNECT 1200\r\n"}
    {pause 1000}
    {send "+++"}
    {expect "+++"}
    {send "atz\r\n"}
    {expect "atz\r\n"}
    {expect "OK\r\n"}
    {send "ato\r\n"}
    {expect "ato\r\n"}
    {send "atz"}
    {expect "atz"}
    {pause 1000}
    {send "+++ath0\r\n"}
    {expect "+++ath0\r\n"}
    {expect "OK\r\n"}
    {expect "NO CARRIER\r\n"}
  }
} -body {
  $modem on
  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test on-4 {Check will accept another inbound connection once one finished} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 1
      type rawtcpip
      speed 1200
    }
  }
  set port [testHelpers::findUnusedPort]
  dict set config inbound port $port
  lassign [chatter::init] inRead outWrite
  set phonebook [Phonebook new]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript {
    {expect "RING\r\n"}
    {expect "CONNECT 1200\r\n"}
    {send "how do you do\r\n"}
    {expect "how do you do\r\n"}
    {pause 1000}
    {send "+++"}
    {expect "+++"}
    {send "ath\r\n"}
    {expect "ath\r\n"}
    {expect "OK\r\n"}
    {expect "NO CARRIER\r\n"}
  }
} -body {
  $modem on
  testHelpers::connect $port
  chatter::chat $chatScript
  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test on-5 {Check will only accept one inbound connection at a time} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 1
      type rawtcpip
      speed 1200
    }
  }
  set port [testHelpers::findUnusedPort]
  dict set config inbound port $port
  lassign [chatter::init] inRead outWrite
  set phonebook [Phonebook new]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript {
    {expect "RING\r\n"}
    {expect "CONNECT 1200\r\n"}
    {send "how do you do\r\n"}
    {expect "how do you do\r\n"}
  }
} -body {
  $modem on
  testHelpers::connect $port
  chatter::chat $chatScript
  testHelpers::connect $port
} -cleanup {
  $modem off
  testHelpers::closeRemote
  chatter::close
} -result {0}


test on-6 {Check can use ATDT to make an outbound connection} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 1
      type rawtcpip
      speed 1200
    }
    outbound_defaults {
      port 23
      speed 1200
      type telnet
    }
  }
  set echoPort [testHelpers::listen]
  set inboundPort [testHelpers::findUnusedPort]
  dict set config inbound port $inboundPort
  lassign [chatter::init] inRead outWrite
  set phonebook [Phonebook new]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript [list \
    [list send "ATDTlocalhost:$echoPort\r\n"] \
    [list expect "ATDTlocalhost:$echoPort\r\n"] \
    {expect "OK\r\n"} \
    {expect "CONNECT 1200\r\n"} \
    {send "how do you do\r\n"} \
    {expect "how do you do\r\n"} \
  ]
} -body {
  $modem on
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::stopListening
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test on-7 {Check won't accept inbound connection if making an outbound connection} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 1
      type rawtcpip
      speed 1200
    }
    outbound_defaults {
      port 23
      speed 1200
      type telnet
    }
  }
  set echoPort [testHelpers::listen]
  set inboundPort [testHelpers::findUnusedPort]
  dict set config inbound port $inboundPort
  lassign [chatter::init] inRead outWrite
  set phonebook [Phonebook new]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript [list \
    [list send "ATDT localhost:$echoPort\r\n"] \
    [list expect "ATDT localhost:$echoPort\r\n"] \
    {expect "OK\r\n"} \
    {expect "CONNECT 1200\r\n"} \
    {send "how do you do\r\n"} \
    {expect "how do you do\r\n"} \
  ]
} -body {
  $modem on
  chatter::chat $chatScript
  testHelpers::connect $inboundPort
} -cleanup {
  $modem off
  testHelpers::stopListening
  testHelpers::closeRemote
  chatter::close
} -result {0}


test on-8 {Check can use ATDT via a phonebook} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 0
      type rawtcpip
      speed 1200
    }
    outbound_defaults {
      port 23
      speed 1200
      type telnet
    }
  }

  set echoPort [testHelpers::listen]
  lassign [chatter::init] inRead outWrite
  set phonebookConfig [
    dict create 123 [dict create hostname localhost \
                                 port $echoPort]
  ]
  set phonebook [
    Phonebook new [dict get $config outbound_defaults] $phonebookConfig
  ]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript [list \
    [list send "ATDT123\r\n"] \
    [list expect "ATDT123\r\n"] \
    {expect "OK\r\n"} \
    {expect "CONNECT 1200\r\n"} \
    {send "how do you do\r\n"} \
    {expect "how do you do\r\n"} \
  ]
} -body {
  $modem on
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::stopListening
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test on-9 {Check when using ATDT that name is looked up in phonebook, instead of just direct telnetting to site} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 0
      type rawtcpip
      speed 1200
    }
    outbound_defaults {
      port 23
      speed 1200
      type telnet
    }
  }

  set echoPort [testHelpers::listen]
  lassign [chatter::init] inRead outWrite
  set phonebookConfig [
    dict create localhost [dict create hostname localhost \
                                       port $echoPort]
  ]
  set phonebook [
    Phonebook new [dict get $config outbound_defaults] $phonebookConfig
  ]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript [list \
    [list send "ATDTlocalhost\r\n"] \
    [list expect "ATDTlocalhost\r\n"] \
    {expect "OK\r\n"} \
    {expect "CONNECT 1200\r\n"} \
    {send "how do you do\r\n"} \
    {expect "how do you do\r\n"} \
  ]
} -body {
  $modem on
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::stopListening
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test on-10 {Check when using ATDT that if name is not in phonebook and not a valid hostname then reports NO CARRIER} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 0
      type rawtcpip
      speed 1200
    }
  }

  lassign [chatter::init] inRead outWrite
  set phonebook [Phonebook new]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript [list \
    [list send "ATDT0\r\n"] \
    [list expect "ATDT0\r\n"] \
    {expect "OK\r\n"} \
    {expect "NO CARRIER\r\n"} \
  ]
} -body {
  $modem on
  chatter::chat $chatScript
} -cleanup {
  $modem off
  chatter::close
} -result {no errors}


test on-11 {Check will use incoming->speed from config for an incoming connection if specified} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 1
      type rawtcpip
      speed 9600
    }
  }
  set port [testHelpers::findUnusedPort]
  dict set config inbound port $port
  lassign [chatter::init] inRead outWrite
  set phonebook [Phonebook new]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript {
    {expect "RING\r\n"}
    {expect "CONNECT 9600\r\n"}
  }
} -body {
  $modem on
  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test on-12 {Check will use the default outbound speed from config for an outgoing connection if specified} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 1
      type rawtcpip
      speed 1200
    }
    outbound_defaults {
      port 23
      speed 9600
      type telnet
    }
  }
  set echoPort [testHelpers::listen]
  set inboundPort [testHelpers::findUnusedPort]
  dict set config inbound port $inboundPort
  lassign [chatter::init] inRead outWrite
  set phonebook [Phonebook new]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript [list \
    [list send "ATDTlocalhost:$echoPort\r\n"] \
    [list expect "ATDTlocalhost:$echoPort\r\n"] \
    {expect "OK\r\n"} \
    {expect "CONNECT 9600\r\n"} \
  ]
} -body {
  $modem on
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::stopListening
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test on-13 {Recognize +++ath0 and escape to command mode when sequence joined for inbound connection} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 1
      type rawtcpip
      speed 1200
    }
  }
  set port [testHelpers::findUnusedPort]
  dict set config inbound port $port
  lassign [chatter::init] inRead outWrite
  set phonebook [Phonebook new]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript {
    {expect "RING\r\n"}
    {expect "CONNECT 1200\r\n"}
    {pause 1000}
    {send "+++ath0\r\n"}
    {expect "+++ath0\r\n"}
    {expect "OK\r\n"}
    {expect "NO CARRIER\r\n"}
  }
} -body {
  $modem on
  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test on-14 {Check will recognize +++ and escape to command mode for an outbound connection} -setup {
  set config {
    inbound {
      ring_on_connect 1
      wait_for_ata 0
      auto_answer 1
      type rawtcpip
      speed 1200
    }
    outbound_defaults {
      port 23
      speed 1200
      type telnet
    }
  }
  set echoPort [testHelpers::listen]
  set inboundPort [testHelpers::findUnusedPort]
  dict set config inbound port $inboundPort
  lassign [chatter::init] inRead outWrite
  set phonebook [Phonebook new]
  set modem [Modem new $config $phonebook $inRead $outWrite]
  set chatScript [list \
    [list send "ATDTlocalhost:$echoPort\r\n"] \
    [list expect "ATDTlocalhost:$echoPort\r\n"] \
    {expect "OK\r\n"} \
    {expect "CONNECT 1200\r\n"} \
    {send "how do you do\r\n"} \
    {expect "how do you do\r\n"} \
    {pause 1000} \
    {send "+++ath0\r\n"} \
    {expect "+++ath0\r\n"} \
    {expect "OK\r\n"} \
    {expect "NO CARRIER\r\n"}
  ]
} -body {
  $modem on
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::stopListening
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


cleanupTests
