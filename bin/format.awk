function grouped(number,   digits, out) {
  digits = sprintf("%d", number)
  while (length(digits) > 3) {
    out = "," substr(digits, length(digits) - 2) out
    digits = substr(digits, 1, length(digits) - 3)
  }
  return digits out
}

function duration(minutes) {
  if (minutes < 60) return minutes "m"
  return int(minutes / 60) "h " minutes % 60 "m"
}
