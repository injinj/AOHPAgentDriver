package org.aohp.agentdriver;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

/** Minimal priv-app placeholder so Cuttlefish AOHP product builds without a prebuilt APK. */
public final class StubMainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView tv = new TextView(this);
        tv.setText(R.string.stub_message);
        tv.setPadding(48, 48, 48, 48);
        setContentView(tv);
    }
}
