# -*- coding: utf-8 -*-
"""
This script calculates an interpolated data point from a grid of data.
Suppose you have Z-axis values, one for each x,y pair of points on a grid 
(the grid does not need to have regularly-spaced points).
This function returns the Z-axis value corresponding to an x,y point that is 
not one of the grid points.

"""
#Initialize
import ads
import numpy as np
import matplotlib.pyplot as plt
from scipy.interpolate import griddata
plt.ioff()


#---------------BEGIN GENERATE CONTOURS SECTION-------------------------------

#The section below will import and parse raw data from ADS...
Z0=50
Use_Max=True

n,s=ads.Create_Python_ADS_Channel()
GP_ref=n[0,0]

#Extract Data   
ZData=np.real(n[1,::])
GP_Var=n[2,::]

#Derive Load Impedance from Gamma
Gamma=np.abs(GP_Var)
Phase=np.angle(GP_Var)

Gamma_ref=np.abs(GP_ref)
Phase_ref=np.angle(GP_ref)

Load_Gammas=Gamma*np.exp(1j*Phase)
Zload=(np.conj(Z0)+Z0*Load_Gammas)/(1-Load_Gammas)

Load_Gamma_Ref=Gamma_ref*np.exp(1j*Phase_ref)
Zload_ref=(np.conj(Z0)+Z0*Load_Gamma_Ref)/(1-Load_Gamma_Ref)

xi_ref=np.real(Zload_ref)
yi_ref=np.imag(Zload_ref)
#
#The section below will generate contours based on the input data
#
#Split the data into R/I
xi=np.real(Zload)
yi=np.imag(Zload)
#

#find the closest point...
cidx=0
errormag=np.zeros((len(Zload),2))
for i in range(0,len(Zload)):
    errormag[i,1]=abs(Zload[i]-Zload_ref)
    errormag[i,0]=i
#Sort
errormag=errormag[errormag[:,1].argsort()]

Ax=np.zeros(int(len(Zload)/4))
Ay=np.zeros(int(len(Zload)/4))
A=Zload[int(errormag[0,0])]-Zload_ref
for i in range(0,int(len(Zload)/4)):
    Arr=(Zload[int(errormag[i,0])]-A)
    Ax[i]=np.real(Arr)
    Ay[i]=np.imag(Arr)

xgrid, ygrid = np.meshgrid(Ax, Ay)

#Generate Contour Level Array
if (Use_Max):
    Min_Value=np.min(ZData)
    fill_value_v=Min_Value
else:
    Max_Value=np.max(ZData)
    fill_value_v=Max_Value
    
#Interpolate Z data onto the grid
zgrid= griddata((xi,yi),ZData, (xgrid, ygrid),method='cubic',fill_value=fill_value_v)

ads.Send_to_ADS(zgrid[0,0].real)
ads.Send_to_ADS(zgrid[0,0].imag)

#CLOSE ADS-PYTHON CHANNEL
ads.Close_Python_ADS_Channel()