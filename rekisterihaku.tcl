# rekisterihaku.tcl - Eggdrop script to fetch vehicle details
# created by tuplanolla @ qnet
#
# https://github.com/janihy/rekisterihaku
#
# Script grabbing technical details by the license plate from biltema API and by scraping Trafi Autovertaamo.
#
# Change log:
# 0.04     Implement !mopo, !mp and !mönkijä
# 0.03     Implement !päästöt
# 0.02     Add emissions data
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
  bind pub - !rekisteri Rekisterihaku::printTechnical
  bind pub - !rekkari Rekisterihaku::printTechnical
  bind pub - !auto Rekisterihaku::printTechnical
  bind pub - !mopo Rekisterihaku::printTechnical
  bind pub - !mp Rekisterihaku::printTechnical
  bind pub - !mönkijä Rekisterihaku::printTechnical
  bind pub - !päästöt Rekisterihaku::printEmissions

  # INTERNAL
  variable scriptVersion 0.03

  # PACKAGES
  package require http
  package require tls
  package require json         ;# can be found in package tcllib in debian
  package require tdom
  http::register https 443 ::tls::socket

  proc getEmissions {licenseplate} {
    variable trafi_endpointurl "https://autovertaamo.traficom.fi/trafienergiamerkki/$licenseplate"
    set trafi_response [::http::geturl $trafi_endpointurl -binary true -headers {Referer https://autovertaamo.traficom.fi/etusivu/index}]
    return $trafi_response
  }

  proc printEmissions {nick host user chan text} {
    http::register https 443 ::tls::socket
    variable ignore

    if {(![matchattr $user $ignore]) && [string trim $text] ne ""} {
      set licenseplate [string trim $text]
      set trafi_response [getEmissions $licenseplate]

      if {[::http::ncode $trafi_response] eq 200} {
        set trafiroot [dom parse -html [::http::data $trafi_response] documentElement]
        set co2 [string trim [[$trafiroot selectNodes "(//div\[@class='paastorajakuvaajan-selite clearfix'\]/strong)\[position()=1\]"] text]]
        set fueltype [string trim [[$trafiroot selectNodes "(//div\[@class='col-md-4'\]/div\[@class='tieto-osio'\]\[position()=4\]/h2)"] text]]
        putlog $fueltype

        if {[catch {
          set emissionsresult [regexp {EURO [0-9]} [string trim [[$trafiroot selectNodes "(//div\[@class='col-md-4'\]/div\[@class='tieto-osio'\]/p/strong)"] text]] emissionsclass]}]
          } {
            #puthelp "PRIVMSG $chan :[string toupper $licenseplate]: Ei päästötietoja, varmaan joku vanha dino :/"
            set emissionsclass "EURO 5 tai uudempi"
            #return 0
          }

          switch -glob $fueltype {
            "Dieselöljy" {
              set nox [string trim [$trafiroot selectNodes {string(//tr[@class='kuvaaja'][position()=1]/@data-arvo)}]]
              set hcnox [string trim [$trafiroot selectNodes {string(//tr[@class='kuvaaja'][position()=2]/@data-arvo)}]]
              set co [string trim [$trafiroot selectNodes {string(//tr[@class='kuvaaja'][position()=3]/@data-arvo)}]]
              set pm [string trim [$trafiroot selectNodes {string(//tr[@class='kuvaaja'][position()=4]/@data-arvo)}]]
              set dpf [string trim [[$trafiroot selectNodes "(//div\[@class='hiukkassuodatin-kylla' or @class='hiukkassuodatin-ei'\])"] text]]

              switch -regexp -- $emissionsclass {
                EURO\ [4-6] {
                  puthelp "PRIVMSG $chan :[string toupper $licenseplate]: $emissionsclass [string tolower $fueltype] - CO² $co2, NOx $nox g/km, HC+NOx $hcnox g/km, CO $co g/km, PM $pm g/km, DPF: [string tolower $dpf]"
                }
                default {
                  puthelp "PRIVMSG $chan :[string toupper $licenseplate]: $emissionsclass [string tolower $fueltype] - CO² $co2"
                }
              }
            }
            "Bensiini*" {
              set nox [string trim [$trafiroot selectNodes {string(//tr[@class='kuvaaja'][position()=1]/@data-arvo)}]]
              set hc [string trim [$trafiroot selectNodes {string(//tr[@class='kuvaaja'][position()=2]/@data-arvo)}]]
              set co [string trim [$trafiroot selectNodes {string(//tr[@class='kuvaaja'][position()=3]/@data-arvo)}]]
              puthelp "PRIVMSG $chan :[string toupper $licenseplate]: $emissionsclass [string tolower $fueltype] - CO² $co2, NOx $nox g/km, HC $hc g/km, CO $co g/km"
            }
          }
        } else {
          puthelp "PRIVMSG $chan :[string toupper $licenseplate]: Ei päästötietoja, varmaan joku vanha dino :/"
        }
      }
    }

  proc printTechnical {nick host user chan text} {
    global lastbind
    http::register https 443 ::tls::socket
    variable ignore
    variable minlength
    global lastbind

    if {(![matchattr $user $ignore])} {
      if {[string trim $text] ne "" && [string length $text] >= $minlength} {
        set licenseplate [string trim $text]
        variable biltema_endpointurl "https://reko.biltema.com/v1/Reko/carinfo/$licenseplate/3/fi"

        set trafi_response [getEmissions $licenseplate]
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
        } elseif {[string length $licenseplate] < 7} {
          set mopo_endpointurl "https://www.allright.eu/vehicle"
          switch $lastbind {
            "!mopo" {
              set data [::http::formatQuery vehicle_type "mo" license $licenseplate]
            }
            "!mp" {
              set data [::http::formatQuery vehicle_type "mp" license $licenseplate]
            }
            "!mönkijä" {
              set data [::http::formatQuery vehicle_type "at" license $licenseplate]
            }
          }
          set mopo_response [::http::geturl $mopo_endpointurl -query $data]
          upvar \#0 $mopo_response state
          set cookies [list]
          foreach {name value} $state(meta) {
             if { $name eq "Set-Cookie" } {
                 lappend cookies [lindex [split $value {;}] 0]
             }
          }
          set mopo_endpointurl "https://www.allright.eu/tuotteet/varaosat"
          ::http::cleanup $mopo_response
          set mopo_response [::http::geturl $mopo_endpointurl -headers [list Cookie [join $cookies {;}]]]
          #putlog [::http::ncode $mopo_response]
          set moporoot [dom parse -html [::http::data $mopo_response] documentElement]

          if {[catch [set mopoinfo [[$moporoot selectNodes "//h4/text()"] data]]]} {
            puthelp "PRIVMSG $chan :[string toupper $licenseplate]: $mopoinfo"
          }

          # catch {puthelp "PRIVMSG $chan :[string toupper $licenseplate]: $mopoinfo"}
        }
      }
    }

    ::http::cleanup $biltema_response
    ::http::cleanup $trafi_response

    # change to return 0 if you want the pubm trigger logged additionally..
    return 1
  }

    proc printMopo {nick host user chan text} {
    }


  putlog "Initialized Rekisterihaku v$scriptVersion"
}
