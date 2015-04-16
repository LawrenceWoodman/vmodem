package require Tcl 8.6
package require tcltest
namespace import tcltest::*

# Add module dir to tm paths
set ThisScriptDir [file dirname [info script]]
set LibDir [file normalize [file join $ThisScriptDir .. lib]]

source [file join $ThisScriptDir "test_helpers.tcl"]
source [file join $ThisScriptDir "chatter.tcl"]
source [file join $LibDir "logger.tcl"]
source [file join $LibDir "rawtcp.tcl"]
source [file join $LibDir "telnet.tcl"]


test connect-1 {Outputs CONNECT message to local when connected} -setup {
  testHelpers::createFakeModem

  lassign [chatter::init] inRead outWrite
  set echoPort [testHelpers::rawEchoListen]
  set telnet [Telnet new $inRead $outWrite 0 0]
  set chatScript {
    {expect "CONNECT 1200"}
  }
} -body {
  $telnet connect localhost $echoPort
  chatter::chat $chatScript
} -cleanup {
  $telnet close
  testHelpers::stopListening
  testHelpers::closeRemote
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


test connect-2 {Outputs NO CARRIER message to local when failed to connect} -setup {
  testHelpers::createFakeModem

  set unusedPort [testHelpers::findUnusedPort]
  lassign [chatter::init] inRead outWrite
  set telnet [Telnet new $inRead $outWrite 0 0]
  set chatScript {
    {expect "NO CARRIER"}
  }
} -body {
  $telnet connect localhost $unusedPort
  chatter::chat $chatScript
} -cleanup {
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


test connect-3 {Check can send and receive data} -setup {
  testHelpers::createFakeModem

  lassign [chatter::init] inRead outWrite
  set echoPort [testHelpers::rawEchoListen]
  set telnet [Telnet new $inRead $outWrite 0 0]

  set chatScript {
    {expect "CONNECT 1200"}
    {send "this was sent from local"}
    {expect "ECHO: this was sent from local"}
    {send "so was this"}
    {expect "ECHO: so was this"}
    {sendBinary {0x23 0xff 0x44}}
    {expectBinary {0x45 0x43 0x48 0x4f 0x3a 0x20 0x23 0xff 0x44}}
  }
} -body {
  $telnet connect localhost $echoPort
  chatter::chat $chatScript
} -cleanup {
  $telnet close
  testHelpers::stopListening
  testHelpers::closeRemote
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


test connect-4 {Check detects when remote connection has dropped and send a NO CARRIER message} -setup {
  testHelpers::createFakeModem

  lassign [chatter::init] inRead outWrite
  set echoPort [testHelpers::rawEchoListen]
  set telnet [Telnet new $inRead $outWrite 0 0]
  set chatScript {
    {expect "CONNECT 1200"}
    {expect "NO CARRIER"}
  }
} -body {
  $telnet connect localhost $echoPort
  after 100 ::testHelpers::closeRemote
  $telnet maintainConnection
  chatter::chat $chatScript
} -cleanup {
  $telnet close
  testHelpers::stopListening
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


test connect-5 {Check will escape 0xFF when sent} -setup {
  testHelpers::createFakeModem

  lassign [chatter::init] inRead outWrite
  set echoPort [testHelpers::rawEchoListen decr]
  set telnet [Telnet new $inRead $outWrite 0 0]

  set chatScript {
    {expect {CONNECT 1200}}
    {sendBinary {0x23 0xff 0x44}}
    {expectBinary {0x22 0xfe 0xfe 0x43}}
  }
} -body {
  $telnet connect localhost $echoPort
  chatter::chat $chatScript
} -cleanup {
  $telnet close
  testHelpers::stopListening
  testHelpers::closeRemote
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


test connect-6 {Check will recognize escaped 0xFF when received} -setup {
  testHelpers::createFakeModem

  lassign [chatter::init] inRead outWrite
  set echoPort [testHelpers::rawEchoListen decr]
  set telnet [Telnet new $inRead $outWrite 0 0]

  set chatScript {
    {expect {CONNECT 1200}}
    {sendBinary {0x23 0x00 0x00 0x44}}
    {expectBinary {0x22 0xff 0x43}}
  }
} -body {
  $telnet connect localhost $echoPort
  chatter::chat $chatScript
} -cleanup {
  $telnet close
  testHelpers::stopListening
  testHelpers::closeRemote
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


test listen-1 {Outputs CONNECT message to local when connected} -setup {
  testHelpers::createFakeModem

  lassign [chatter::init] inRead outWrite
  set telnet [Telnet new $inRead $outWrite 0 0]
  set chatScript {
    {expect "CONNECT 1200"}
  }
} -body {
  set foundPort 0
  set port 1024

  while {!$foundPort} {
    try {
      $telnet listen $port
      set foundPort 1
    } on error {} {
      incr port
    }
  }

  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $telnet close
  testHelpers::closeRemote
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


test listen-2 {Outputs RING message to local when receives connection if requested} -setup {
  testHelpers::createFakeModem

  lassign [chatter::init] inRead outWrite
  set telnet [Telnet new $inRead $outWrite 1 0]
  set chatScript {
    {expect "RING"}
    {expect "CONNECT 1200"}
  }
} -body {
  set foundPort 0
  set port 1024

  while {!$foundPort} {
    try {
      $telnet listen $port
      set foundPort 1
    } on error {} {
      incr port
    }
  }

  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $telnet close
  testHelpers::closeRemote
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


cleanupTests
