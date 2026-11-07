import Base
import ../src/cli/duration.bend as D

# Spec for src/cli/duration.bend: k8s.io/apimachinery util/duration
# HumanDuration. Expected values come from running the vendored Go
# (vcluster/vendor/k8s.io/apimachinery/pkg/util/duration/duration.go).

law duration.s0:
  {D.Dur.human(0) == "0s" : String}

law duration.s1:
  {D.Dur.human(1) == "1s" : String}

law duration.s59:
  {D.Dur.human(59) == "59s" : String}

law duration.s119:
  {D.Dur.human(119) == "119s" : String}

law duration.s120:
  {D.Dur.human(120) == "2m" : String}

law duration.s121:
  {D.Dur.human(121) == "2m1s" : String}

law duration.s179:
  {D.Dur.human(179) == "2m59s" : String}

law duration.s540:
  {D.Dur.human(540) == "9m" : String}

law duration.s599:
  {D.Dur.human(599) == "9m59s" : String}

law duration.s600:
  {D.Dur.human(600) == "10m" : String}

law duration.s659:
  {D.Dur.human(659) == "10m" : String}

law duration.s10799:
  {D.Dur.human(10799) == "179m" : String}

law duration.s10800:
  {D.Dur.human(10800) == "3h" : String}

law duration.s14400:
  {D.Dur.human(14400) == "4h" : String}

law duration.s14460:
  {D.Dur.human(14460) == "4h1m" : String}

law duration.s28799:
  {D.Dur.human(28799) == "7h59m" : String}

law duration.s28800:
  {D.Dur.human(28800) == "8h" : String}

law duration.s172799:
  {D.Dur.human(172799) == "47h" : String}

law duration.s172800:
  {D.Dur.human(172800) == "2d" : String}

law duration.s176400:
  {D.Dur.human(176400) == "2d1h" : String}

law duration.s691199:
  {D.Dur.human(691199) == "7d23h" : String}

law duration.s691200:
  {D.Dur.human(691200) == "8d" : String}

law duration.s63071999:
  {D.Dur.human(63071999) == "729d" : String}

law duration.s63072000:
  {D.Dur.human(63072000) == "2y" : String}

law duration.s63158400:
  {D.Dur.human(63158400) == "2y1d" : String}

law duration.s252287999:
  {D.Dur.human(252287999) == "7y364d" : String}

law duration.s252288000:
  {D.Dur.human(252288000) == "8y" : String}

law duration.s315360000:
  {D.Dur.human(315360000) == "10y" : String}
