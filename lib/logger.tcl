#
# Control logging of information to a file
#
# Copyright (C) 2015 Lawrence Woodman <lwoodman@vlifesystems.com>
#
# Licensed under an MIT licence.  Please see LICENCE.md for details.
#
namespace eval logger {
  package require cmdline
  variable logFID
  variable active 0
  variable lastLevel
  variable lastMsg
  variable supressedLevels {}
}


proc logger::init {{filename {}}} {
  variable logFID
  variable active
  variable lastLevel
  variable lastMsg

  if {$filename eq {}} {
    set logFID stdout
  } else {
    if {[catch {open $filename a} logFID]} {
      error "Couldn't open $filename for logging"
    }
  }

  set active 1
  set lastLevel ""
  set lastMsg ""
}


proc logger::supressLevel {level {supress 1}} {
  variable supressedLevels

  if {![IsValidLevel $level]} {
    return -code error "invalid level: $level"
  }

  set i [lsearch $supressedLevels $level]
  if {$supress} {
    if {$i == -1} {lappend supressedLevels $level}
  } else {
    if {$i != -1} {
      set supressedLevels [lreplace $supressedLevels $i $i]
    }
  }
}


proc logger::close {} {
  variable logFID
  variable active

  if {!$active} {return}
  ::close $logFID
}


proc logger::log {args} {
  variable logFID
  variable active
  variable lastLevel
  variable lastMsg
  variable supressedLevels

  if {!$active} {return}

  set options {
    {noheader {Don't add timestamp and level header}}
  }

  set usage ": log \[options] \[level] msg\noptions:"
  set params [::cmdline::getoptions args $options $usage]

  if {[llength $args] != 2} {
    puts stderr "Error: Wrong number of arguments"
    return -code error [::cmdline::usage $options $usage]
  }

  lassign $args level msg
  if {![IsValidLevel $level]} {
    return -code error "invalid level: $level"
  }

  if {$level in $supressedLevels} {return}


  if {$level in {error critical} && $lastLevel eq $level && $lastMsg eq $msg} {
    return
  } else {
    set lastLevel $level
    set lastMsg $msg
  }

  if {[dict get $params noheader]} {
    set formattedMsg $msg
  } else {
    set currentTime [clock seconds]
    set formattedTime [clock format $currentTime -format {%Y-%m-%d %H:%M:%S}]
    set formattedMsg [format "%19s  %9s  %s" $formattedTime $level $msg]
  }

  puts $logFID $formattedMsg
  flush $logFID
}


proc logger::eval {args} {
  set options {
    {noheader {Don't add timestamp and level header}}
  }

  set usage ": eval \[options] \[level] script\noptions:"
  set params [::cmdline::getoptions args $options $usage]

  switch [llength $args] {
    1 {
      lassign $args script
      set level info
    }
    2 {
      lassign $args level script
    }
    - {
      puts stderr "Error: Wrong number of arguments"
      ::cmdline::usage $options $usage
    }
  }

  set result [uplevel 1 $script]

  if {[dict get $params noheader]} {
    log -noheader $level $result
  } else {
    log $level $result
  }
}


proc logger::dumpBytes {bytes} {
  set byteNum 0
  set numBytes [llength $bytes]
  set dump ""

  for {set byteNum 0} {$byteNum < $numBytes} {incr byteNum 16} {
    set next16Bytes [lrange $bytes $byteNum $byteNum+15]
    set line [
      format {    0x%04X:  %-40s %s} \
             $byteNum \
             [DumpHexBytes $next16Bytes] \
             [DumpASCIIBytes $next16Bytes]
    ]
    append dump "$line\n"
  }

  return [string trimright $dump]
}



######################
# Internal commands
######################
proc logger::DumpHexBytes {bytes} {
  set byteNum 0
  set dump ""

  foreach ch $bytes {
    binary scan $ch c signedByte
    set unsignedByte [expr {$signedByte & 0xff}]
    append dump [format {%02x} $unsignedByte]
    if {$byteNum % 2 == 1} {
      append dump " "
    }
    incr byteNum
  }

  return $dump
}


proc logger::DumpASCIIBytes {bytes} {
  set dump ""

  foreach ch $bytes {
    if {[string is print $ch]} {
      append dump $ch
    } else {
      append dump "."
    }
  }

  return $dump
}


proc logger::IsValidLevel {level} {
  set validLevels {debug info notice error critical}
  exp {$level in $validLevels}
}
