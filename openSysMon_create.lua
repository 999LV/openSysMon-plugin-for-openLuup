do
  local dev = luup.create_device ('', "OSM", "openSysMon", "D_openSysMon.xml", "I_openSysMon.xml")
  print("openWeather device created... device number = " .. dev)
end
