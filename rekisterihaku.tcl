# rekisterihaku.tcl - Eggdrop script to fetch vehicle details
# created by tuplanolla @ qnet
#
# https://github.com/janihy/rekisterihaku
#
# Script grabbing technical details by the license plate from biltema API
#
# Change log:
# 0.01     Initial version
#
################################################################################################################
#
# Usage:
#
# 1) !rekisteri abc-123
#
################################################################################################################

namespace eval Rekisterihaku {
  # CONFIG
  variable ignore "bdkqr|dkqr" ;# User flags script will ignore input from
  variable length 7            ;# minimum url length to trigger channel eggdrop use
  variable timeout 5000        ;# geturl timeout (1/1000ths of a second)
  variable fetchLimit 5        ;# How many times to process redirects before erroring

  # BINDS
  bind pub - !rekisteri Rekisterihaku::handler

  # INTERNAL
  variable scriptVersion 0.01

  # PACKAGES
  package require http         ;# You need the http package..
  package require tls
  package require json         ;# from package tcllib in debian

  proc handler {nick host user chan text} {
    variable ignore
    variable length
    http::register https 443 ::tls::socket

    if {(![matchattr $user $ignore])} {
      if {[string trim $text] ne "" && [string length $text] >= $length} {
        variable endpointurl "https://reko.biltema.com/v1/Reko/carinfo/$text/3/fi"
        set response [::http::data [::http::geturl $endpointurl -binary true]]
        set parsed [::json::json2dict $response]

        set suomiauto [expr {[string equal [dict get $parsed imported] true] ? "" : ", suomiauto"}]
        set firstreg [string trimleft [string range [dict get $parsed registrationDate] 6 7] 0].[string trimleft [string range [dict get $parsed registrationDate] 4 5] 0].[string range [dict get $parsed registrationDate] 0 3]
        puthelp "PRIVMSG $chan :[dict get $parsed licensePlateNbr]: [dict get $parsed nameOfTheCar] [dict get $parsed modelYear]. [dict get $parsed engineCode] - [dict get $parsed powerKw] kW [dict get $parsed cylinderCapacityCcm] cm³ [dict get $parsed cylinder]-syl [string tolower [dict get $parsed fuelType]]. Ensirekisteröinti $firstreg, VIN [dict get $parsed chassieNumber]$suomiauto"
      }
    }

    # change to return 0 if you want the pubm trigger logged additionally..
    return 1
  }

  putlog "Initialized Rekisterihaku v$scriptVersion"
}
