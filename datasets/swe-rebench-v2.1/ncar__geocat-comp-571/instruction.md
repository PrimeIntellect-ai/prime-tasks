geocat.comp.meteorology.delta_pressure is different with dpres_plev
###this is the ncl  code
plev = (/ 1000.,950.,900.,850.,800.,750.,700.,650.,600., \
    550.,500.,450.,400.,350.,300.,250.,200., \
    175.,150.,125.,100., 80., 70., 60., 50., \
     40., 30., 25., 20. /)


plev       = plev*100.
plev@units = "Pa"        ; Pa   =  kg/(m s2) (Pascal)


ptop       = min(plev)

psfc       = 850*100.
psfc@units = "Pa"

dp   = dpres_plevel(plev, psfc, ptop, 0)  ; dp(30)
print(dp)





##this is the python code:
import geocat.comp as gc
import numpy as np
plev = [ 1000.,950.,900.,850.,800.,750.,700.,650.,600., \
    550.,500.,450.,400.,350.,300.,250.,200., \
    175.,150.,125.,100., 80., 70., 60., 50., \
     40., 30., 25., 20. ]
plev       = np.array(plev)*100.
ptop       = min(plev)
psfc       = 850*100.
dp   = gc.meteorology.delta_pressure(plev, psfc)
print(dp)

but the result is different if the psfc is lower than the first value of plev
![屏幕截图 2024-01-05 162143](https://github.com/NCAR/geocat-comp/assets/98377186/649ccf69-99cc-4a99-9b33-8d182814cc21)
![屏幕截图 2024-01-05 162521](https://github.com/NCAR/geocat-comp/assets/98377186/fe282ef1-360f-49d1-b9b4-01c36dd0339a)
