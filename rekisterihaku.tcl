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
  variable ignore "bdkqr|dkqr" ;# user flags script will ignore input from
  variable minlength 7         ;# minimum license plate length to query

  # BINDS
  bind pub - !rekisteri Rekisterihaku::handler

  # INTERNAL
  variable scriptVersion 0.01

  # PACKAGES
  package require http
  package require tls
  package require json         ;# can be found in package tcllib in debian

  proc handler {nick host user chan text} {
    variable ignore
    variable minlength
    http::register https 443 ::tls::socket

    if {(![matchattr $user $ignore])} {
      if {[string trim $text] ne "" && [string length $text] >= $minlength} {
        set licenseplate [string trim $text]
        variable endpointurl "https://reko.biltema.com/v1/Reko/carinfo/$licenseplate/3/fi"

        set response [::http::geturl $endpointurl -binary true]

        if {[::http::ncode $response] eq 200} {
          set parsed [::json::json2dict [::http::data $response]]
          if {[dict size $parsed] < 26} {
            putlog "$licenseplate: $parsed"
            puthelp "PRIVMSG $chan :Cannot parse the API response."
          }

          set suomiauto [expr {[string equal [dict get $parsed imported] true] ? "" : ", suomiauto"}]
          set firstreg [string trimleft [string range [dict get $parsed registrationDate] 6 7] 0].[string trimleft [string range [dict get $parsed registrationDate] 4 5] 0].[string range [dict get $parsed registrationDate] 0 3]
          set massat [dict get $parsed weightKg]/[dict get $parsed maxWeightKg]
          puthelp "PRIVMSG $chan :[dict get $parsed licensePlateNbr]: [dict get $parsed nameOfTheCar] [dict get $parsed modelYear]. [dict get $parsed powerKw] kW [dict get $parsed cylinderCapacityCcm] cm³ [dict get $parsed cylinder]-syl [string tolower [dict get $parsed fuelType]] [string tolower [dict get $parsed impulsionType]] ([dict get $parsed engineCode]). Oma/kokonaismassa $massat kg. Ensirekisteröinti $firstreg, VIN [dict get $parsed chassieNumber]$suomiauto"
        }
        ::http::cleanup $response
      }
    }

    # change to return 0 if you want the pubm trigger logged additionally..
    return 1
  }

  putlog "Initialized Rekisterihaku v$scriptVersion"
}
