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
  variable minlength 3         ;# minimum license plate length to query

  # BINDS
  bind pub - !rekisteri Rekisterihaku::handler

  # INTERNAL
  variable scriptVersion 0.01

  # PACKAGES
  package require http
  package require tls
  package require json         ;# can be found in package tcllib in debian
  package require tdom

  proc handler {nick host user chan text} {
    variable ignore
    variable minlength
    http::register https 443 ::tls::socket

    if {(![matchattr $user $ignore])} {
      if {[string trim $text] ne "" && [string length $text] >= $minlength} {
        set licenseplate [string trim $text]
        variable biltema_endpointurl "https://reko.biltema.com/v1/Reko/carinfo/$licenseplate/3/fi"
        variable trafi_endpointurl "https://autovertaamo.traficom.fi/trafienergiamerkki/$licenseplate"

        set trafi_response [::http::geturl $trafi_endpointurl -binary true -headers {Referer https://autovertaamo.traficom.fi/etusivu/index}]
        set biltema_response [::http::geturl $biltema_endpointurl -binary true]

        if {[::http::ncode $biltema_response] eq 200} {
          set parsed [::json::json2dict [::http::data $biltema_response]]
          if {[dict size $parsed] < 26} {
            putlog "$licenseplate: $parsed"
            puthelp "PRIVMSG $chan :Cannot parse the API biltema_response."
          }

          set firstreg [string trimleft [string range [dict get $parsed registrationDate] 6 7] 0].[string trimleft [string range [dict get $parsed registrationDate] 4 5] 0].[string range [dict get $parsed registrationDate] 0 3]
          set massat [dict get $parsed weightKg]/[dict get $parsed maxWeightKg]
          set suomiauto [expr {[string equal [dict get $parsed imported] true] ? "" : ", suomiauto"}]

          if {[::http::ncode $trafi_response] eq 200} {
            set trafiroot [dom parse -html [::http::data $trafi_response] documentElement]

            set taxTotal [string trim [[$trafiroot selectNodes "(//div\[@class='col-md-4'\]/div\[@class='tieto-osio'\]/h2)\[position()=2\]"] text]]
            set co2 [string trim [[$trafiroot selectNodes "(//div\[@class='paastorajakuvaajan-selite clearfix'\]/strong)\[position()=1\]"] text]]
            set fuelConsumptionCombined [string trim [[$trafiroot selectNodes "(//div\[@class='col-md-4'\]/div\[@class='tieto-osio'\]/div/span)\[position()=3\]"] text]]
            set fuelConsumptionExtraUrban [string trim [[$trafiroot selectNodes "(//div\[@class='col-md-4'\]/div\[@class='tieto-osio'\]/div/span)\[position()=4\]"] text]]
            set fuelConsumptionUrban [string trim [[$trafiroot selectNodes "(//div\[@class='col-md-4'\]/div\[@class='tieto-osio'\]/div/span)\[position()=5\]"] text]]

            puthelp "PRIVMSG $chan :[dict get $parsed licensePlateNbr]: [dict get $parsed nameOfTheCar] [dict get $parsed modelYear]. [dict get $parsed powerKw] kW [dict get $parsed cylinderCapacityCcm] cm³ [dict get $parsed cylinder]-syl [string tolower [dict get $parsed fuelType]] [string tolower [dict get $parsed impulsionType]] ([dict get $parsed engineCode]). Ajoneuvovero $taxTotal, CO² $co2, kulutus $fuelConsumptionCombined/$fuelConsumptionExtraUrban/$fuelConsumptionUrban l/100 km. Oma/kokonaismassa $massat kg. Ensirekisteröinti $firstreg, VIN [dict get $parsed chassieNumber]$suomiauto"
          } else {
            puthelp "PRIVMSG $chan :[dict get $parsed licensePlateNbr]: [dict get $parsed nameOfTheCar] [dict get $parsed modelYear]. [dict get $parsed powerKw] kW [dict get $parsed cylinderCapacityCcm] cm³ [dict get $parsed cylinder]-syl [string tolower [dict get $parsed fuelType]] [string tolower [dict get $parsed impulsionType]] ([dict get $parsed engineCode]). Ei päästö- tai verotietoja. Oma/kokonaismassa $massat kg. Ensirekisteröinti $firstreg, VIN [dict get $parsed chassieNumber]$suomiauto"
          }
        }

        ::http::cleanup $biltema_response
        ::http::cleanup $trafi_response
        }
      }

    # change to return 0 if you want the pubm trigger logged additionally..
    return 1
  }

  putlog "Initialized Rekisterihaku v$scriptVersion"
}
