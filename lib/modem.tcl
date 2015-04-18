#
# Emulate the hayes modem command interface.
#
# Copyright (C) 2015 Lawrence Woodman <lwoodman@vlifesystems.com>
#
# Licensed under an MIT licence.  Please see LICENCE.md for details.
#
namespace eval modem {
  set LibDir [file dirname [info script]]
  source [file join $LibDir rawtcp.tcl]
  source [file join $LibDir telnet.tcl]

  variable mode "off"
  variable line ""
  variable speed 1200
  variable config
  variable transport {}
}


proc modem::emulateModem {_config} {
  variable mode
  variable config
  variable transport
  set config $_config

  dict with config {
    set transport [
      dict create telnet [Telnet new stdin stdout \
                                     $ring_on_connect $wait_for_ata] \
                  rawtcp [RawTcp new stdin stdout \
                                     $ring_on_connect $wait_for_ata]
    ]
    set problem [
      catch {
        chan configure stdin -translation binary -blocking 0 -buffering none
        chan configure stdout -translation binary -blocking 0 -buffering none
        chan event stdin readable [list ::modem::ReceiveFromStdin]

        changeMode "command"
        while {$mode ne "off"} {
          if {$auto_answer} {
            if {$incoming_type eq "telnet" || $incoming_type eq "rawtcp"} {
              set transportInst [dict get $transport $incoming_type]
              $transportInst listen $incoming_port
            }
          }
          vwait ::modem::mode
        }
      } result options
    ]
  }

  if {$problem} {
    logger::log critical "result: $result\noptions: $options"
    # report the error with original details
    dict unset options -level
    return -options $options $result
  }

  # TODO: Trap signls so that can close neatly
  logger::close
}


proc modem::changeMode {newMode} {
  variable mode

  if {$mode ne $newMode} {
    logger::log info "Entering $newMode mode"
    set mode $newMode
  }
}


########################
# Internal Commands
########################
proc modem::StopListening {} {
  variable transport

  dict for {transportType transportInst} $transport {
    $transportInst stopListening
  }
}


proc modem::ProcessLine {} {
  variable line
  variable config
  variable transport

  set line [string trim $line]
  if {$line ne ""} {
    puts ""

    logger::eval info {
      set bytes [split $line {}]
      set msg "Received line:\n[::logger::dumpBytes $bytes]"
    }
    switch -regexp $line {
      {(?i)^at\s*d[tp"]?.*$} { ;#"
        puts "OK"
        Dial $line
        ::modem::changeMode "command"
      }
      {(?i)^at\s*a} {
        puts "OK"
        set incoming_type [dict get $config incoming_type]
        set transportInst [dict get $transport $incoming_type]
        $transportInst completeInbondConnection
        $transportInst maintainConnection
        ::modem::changeMode "command"
      }

      {(?i)^at.*$} {
        # Acknowledge but ignore any other AT command
        puts "OK"
      }
    }
  }

  set line ""
}


proc modem::GetPhoneNumberDetails {phoneNumber} {
  global phonebook

  if {[dict exists $phonebook $phoneNumber]} {
    set phoneNumberRecord [dict get $phonebook $phoneNumber]
    dict create \
      hostname [dict get $phoneNumberRecord hostname] \
      port [DictGetWithDefault $phoneNumberRecord port 23] \
      speed [DictGetWithDefault $phoneNumberRecord speed 1200] \
      type [DictGetWithDefault $phoneNumberRecord type "telnet"]
  } else {
    return {}
  }
}


proc modem::DictGetWithDefault {dictionary key default} {
  if {[dict exists $dictionary $key]} {
    return [dict get $dictionary $key]
  }

  return $default
}


proc modem::Dial {atdLine} {
  global phonebook
  variable speed
  variable transport

  if {[regexp {(?i)^at\s*d".*:\d+$} $atdLine]} { ; #"
    set hostname [regsub {(?i)^(at\s*d")(.*):(\d+)$} $atdLine {\2}] ; #"
    set port [regsub {(?i)^(at\s*d")(.*):(\d+)$} $atdLine {\3}] ; #"
    set type "telnet"
    set logMsg "Emulating dialing by telnetting to $hostname:$port"
  } elseif {[regexp {(?i)^at\s*d".*$} $atdLine]} { ; #"
    set hostname [regsub {(?i)^(at\s*d")(.*)$} $atdLine {\2}] ; #"
    set port 23
    set type "telnet"
    set logMsg "Emulating dialing by telnetting to $hostname:$port"
  } else {
    set phoneNumber [regsub {(?i)^(at\s*d[tp]?)(.*)$} $atdLine {\2}]
    set details [GetPhoneNumberDetails $phoneNumber]

    if {$details eq {}} {
      logger::log info \
                  "Couldn't find phone number $phoneNumber in phonebook"
      puts "NO CARRIER"
      return
    }

    set hostname [dict get $details hostname]
    set port [dict get $details port]
    set speed [dict get $details speed]
    set type [dict get $details type]

    if {$type eq "telnet"} {
      set logMsg "Emulating dialing $phoneNumber by telnetting to $hostname:$port"
    } else {
      set logMsg "Emulating dialing $phoneNumber by making raw tcp connection to $hostname:$port"
    }
  }

  StopListening

  logger::log info $logMsg
  set transportInst [dict get $transport $type]
  $transportInst connect $hostname $port
  $transportInst maintainConnection
}


proc modem::ReceiveFromStdin {} {
  variable line

  set LF 0x0A
  set CR 0x0D

  if {[catch {read stdin} dataFromStdin]} {
    logger::log error "Couldn't read from stdin"
    return
  }

  set bytesFromStdin [split $dataFromStdin {}]

  foreach ch $bytesFromStdin {
    binary scan $ch c signedByte
    set unsignedByte [expr {$signedByte & 0xff}]
    if {$unsignedByte == $LF || $unsignedByte == $CR} {
      ProcessLine
    } else {
      append line $ch
    }

  }

  if {[catch {puts -nonewline $dataFromStdin}]} {
    logger::log error "Couldn't write to stdout"
    return
  }
}
