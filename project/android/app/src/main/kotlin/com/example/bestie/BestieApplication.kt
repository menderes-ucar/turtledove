package com.example.bestie

import android.app.Activity
import android.app.Application
import android.os.Bundle
import java.util.concurrent.atomic.AtomicInteger

/**
 * Single process-level foreground gate for the incoming-call transport.
 *
 * FCM can arrive while MainActivity is paused/backgrounded. A boolean written
 * from one Activity's onResume/onPause is race-prone and can be stale. Android
 * already tells us when an Activity is actually started/stopped, so the FCM
 * service uses this process-wide counter as the one source of truth.
 */
class BestieApplication : Application() {
    companion object {
        @Volatile
        private var startedActivities = AtomicInteger(0)

        @JvmStatic
        fun isAppForeground(): Boolean = startedActivities.get() > 0
    }

    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: Activity) {
                startedActivities.incrementAndGet()
            }

            override fun onActivityStopped(activity: Activity) {
                startedActivities.updateAndGet { current ->
                    if (current > 0) current - 1 else 0
                }
            }

            override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
            override fun onActivityResumed(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        })
    }
}
