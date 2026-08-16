package com.retrolan.console.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log

/**
 * Advertises the RetroLAN service via Android's NsdManager (mDNS/DNS-SD).
 * Service type: _retrolan._tcp — controllers browse for this.
 *
 * RetroLAN-original code (GPLv3 under /tv-app).
 */
class RetroAdvertiser(private val context: Context) {
    private val TAG = "RetroAdvertiser"
    private var nsdManager: NsdManager? = null
    private var registration: NsdManager.RegistrationListener? = null
    private var registered = false

    fun start() {
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager ?: return
        val service = NsdServiceInfo().apply {
            serviceName = "RetroLAN-${android.os.Build.MODEL}"
            serviceType = "_retrolan._tcp."
            setPort(8877)
        }
        registration = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                registered = true
                Log.i(TAG, "advertised ${info.serviceName}")
            }
            override fun onRegistrationFailed(info: NsdServiceInfo, code: Int) {
                Log.w(TAG, "registration failed code=$code (controllers can use manual IP)")
            }
            override fun onServiceUnregistered(info: NsdServiceInfo) { registered = false }
            override fun onUnregistrationFailed(info: NsdServiceInfo, code: Int) { registered = false }
        }
        try {
            nsdManager?.registerService(service, NsdManager.PROTOCOL_DNS_SD, registration)
        } catch (e: Exception) {
            Log.e(TAG, "register failed", e)
        }
    }

    fun stop() {
        if (registered) {
            try { nsdManager?.unregisterService(registration) } catch (_: Exception) {}
        }
        registered = false
    }
}
