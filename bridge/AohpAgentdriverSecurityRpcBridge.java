/*
 * Reference: copy methods into AOHP AgentDriver JsonCommandHandler (or equivalent).
 * Requires platform / priv-app with MANAGE_AOHP_VIRTUAL_DISPLAY where policy allows.
 *
 * Not compiled by aohp-dev Gradle; build inside the Agent AOSP / app module that links
 * frameworks-base stubs for com.android.internal.aohp.* and android.os.ServiceManager.
 */
package dev.aohp.contrib.agentdriver;

import android.os.IBinder;
import android.os.ServiceManager;

import com.android.internal.aohp.IAohpAgentView;
import com.android.internal.aohp.IAohpSecurityBridge;
import com.android.internal.aohp.IAohpTaintTracker;
import com.android.internal.aohp.IAohpVault;
import com.android.internal.aohp.IAohpVirtualDisplay;

import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONTokener;

/**
 * Maps JSON-RPC method names (aohp CLI / docs) to Binder calls on system_server AOHP services.
 */
public final class AohpAgentdriverSecurityRpcBridge {
    public static final String SVC_VAULT = "aohp_vault";
    public static final String SVC_TAINT = "aohp_taint";
    public static final String SVC_SECURITY = "aohp_security_bridge";
    public static final String SVC_AGENT_VIEW = "aohp_agent_view";
    public static final String SVC_VIRTUAL_DISPLAY = "aohp_virtual_display";

    public interface InputNodeInvoker {
        void actInputNode(int displayId, int nodeId, String text, int flags) throws Exception;
    }

    private AohpAgentdriverSecurityRpcBridge() {}

    private static IAohpVault vault() {
        IBinder b = ServiceManager.getService(SVC_VAULT);
        return b == null ? null : IAohpVault.Stub.asInterface(b);
    }

    private static IAohpTaintTracker taint() {
        IBinder b = ServiceManager.getService(SVC_TAINT);
        return b == null ? null : IAohpTaintTracker.Stub.asInterface(b);
    }

    private static IAohpSecurityBridge security() {
        IBinder b = ServiceManager.getService(SVC_SECURITY);
        return b == null ? null : IAohpSecurityBridge.Stub.asInterface(b);
    }

    private static IAohpAgentView agentView() {
        IBinder b = ServiceManager.getService(SVC_AGENT_VIEW);
        return b == null ? null : IAohpAgentView.Stub.asInterface(b);
    }

    private static IAohpVirtualDisplay virtualDisplay() {
        IBinder b = ServiceManager.getService(SVC_VIRTUAL_DISPLAY);
        return b == null ? null : IAohpVirtualDisplay.Stub.asInterface(b);
    }

    /**
     * @return JSON-serializable result (String, JSONObject, JSONArray, byte[] base64 handled by caller)
     */
    public static Object dispatch(String method, JSONObject params, InputNodeInvoker inputInvoker)
            throws Exception {
        switch (method) {
            case "vault.list": {
                IAohpVault v = vault();
                if (v == null) {
                    return jsonError("vault_service_missing");
                }
                return new JSONArray(v.listEntriesJson());
            }
            case "vault.info": {
                IAohpVault v = vault();
                if (v == null) {
                    return jsonError("vault_service_missing");
                }
                return new JSONObject(v.getInfoJson(params.getString("token")));
            }
            case "vault.revoke": {
                IAohpVault v = vault();
                if (v == null) {
                    return jsonError("vault_service_missing");
                }
                v.revoke(params.getString("token"));
                return JSONObject.NULL;
            }
            case "taint.list": {
                IAohpTaintTracker t = taint();
                if (t == null) {
                    return jsonError("taint_service_missing");
                }
                String filter = params.optString("filterSourceApp", "");
                return new JSONArray(t.listTaintsJson(filter));
            }
            case "taint.list_sensitive": {
                IAohpTaintTracker t = taint();
                if (t == null) {
                    return jsonError("taint_service_missing");
                }
                return new JSONArray(t.listSensitiveTaintsJson());
            }
            case "taint.info": {
                IAohpTaintTracker t = taint();
                if (t == null) {
                    return jsonError("taint_service_missing");
                }
                return new JSONObject(t.getTaintJson(params.getString("taintId")));
            }
            case "security.filter_ui_tree": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                return s.filterUiTreeJson(
                        params.getString("rawTreeJson"),
                        params.getString("foregroundPackage"),
                        params.getInt("displayId"));
            }
            case "security.check_input_policy": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                return new JSONObject(
                        s.checkInputPolicy(
                                params.getString("foregroundPackage"),
                                params.getString("targetResourceId"),
                                params.getString("textOrToken")));
            }
            case "security.check_tap_policy": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                return new JSONObject(
                        s.checkTapPolicy(
                                params.getString("foregroundPackage"),
                                params.getString("targetResourceId")));
            }
            case "security.get_consent_state": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                return s.getConsentState(params.getString("consentId"));
            }
            case "security.audit_tail": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                return s.listAuditTail(params.optInt("maxLines", 100));
            }
            case "security.resolve_vault": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                String plain =
                        s.resolveVaultToken(
                                params.getString("token"), params.optString("purpose", "aohp.rpc"));
                return plain != null ? plain : JSONObject.NULL;
            }
            case "security.register_skill": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                return new JSONObject(
                        s.registerSkillPolicy(
                                params.getString("skillName"),
                                params.getString("securityJson")));
            }
            case "security.filter_file_list_json": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                String raw = s.filterFileListJson(params.getString("rawResultJson"));
                return new JSONTokener(raw).nextValue();
            }
            case "security.check_file_share_policy": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                return new JSONObject(
                        s.checkFileSharePolicy(
                                params.getString("devicePath"),
                                params.optString("targetPackage", "")));
            }
            case "security.check_skill_output_policy": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                String raw =
                        s.checkSkillOutputPolicy(
                                params.getString("skillName"),
                                params.getString("rawOutputJson"));
                return new JSONTokener(raw).nextValue();
            }
            case "security.check_skill_input_policy": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                return new JSONObject(
                        s.checkSkillInputPolicy(
                                params.getString("skillName"),
                                params.getString("paramName"),
                                params.getString("value")));
            }
            case "security.sanitize_event": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                return new JSONObject(s.sanitizeEventJson(params.getString("eventDataJson")));
            }
            /**
             * After resolving a ui.tree node id to coordinates, route taps through this RPC so
             * {@link IAohpVirtualDisplay#injectTapWithTarget} can enforce {@code checkTapPolicy}
             * using the node's declared {@code resourceId} (matches aohp_sensitivity.xml /
             * view id name).
             */
            case "vd.tap_with_target": {
                IAohpVirtualDisplay vd = virtualDisplay();
                if (vd == null) {
                    return jsonError("virtual_display_service_missing");
                }
                boolean ok =
                        vd.injectTapWithTarget(
                                params.getInt("displayId"),
                                params.getInt("x"),
                                params.getInt("y"),
                                params.optString("targetResourceId", ""));
                JSONObject o = new JSONObject();
                o.put("ok", ok);
                return o;
            }
            case "secure.input": {
                if (inputInvoker == null) {
                    return jsonError("input_invoker_missing");
                }
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                String plain =
                        s.resolveVaultToken(
                                params.getString("token"),
                                params.optString("purpose", "aohp.secure_input"));
                if (plain == null) {
                    return jsonError("resolve_failed");
                }
                inputInvoker.actInputNode(
                        params.getInt("displayId"),
                        params.getInt("nodeId"),
                        plain,
                        params.optInt("flags", 0));
                JSONObject ok = new JSONObject();
                ok.put("ok", true);
                return ok;
            }
            case "secure.confirm": {
                IAohpSecurityBridge s = security();
                if (s == null) {
                    return jsonError("security_service_missing");
                }
                s.completeConsent(params.getString("consentId"), params.optBoolean("approved", true));
                JSONObject ok = new JSONObject();
                ok.put("ok", true);
                return ok;
            }
            case "shot.full_redacted": {
                IAohpAgentView av = agentView();
                if (av == null) {
                    return jsonError("agent_view_missing");
                }
                JSONArray a = params.getJSONArray("sensitiveRectFlat");
                int n = a.length();
                int[] flat = new int[n];
                for (int i = 0; i < n; i++) {
                    flat[i] = a.getInt(i);
                }
                byte[] jpeg =
                        av.captureDisplayRedacted(
                                params.getInt("displayId"),
                                params.getInt("quality"),
                                flat);
                if (jpeg == null) {
                    return jsonError("capture_failed");
                }
                return android.util.Base64.encodeToString(jpeg, android.util.Base64.NO_WRAP);
            }
            default:
                return null;
        }
    }

    private static JSONObject jsonError(String code) throws org.json.JSONException {
        JSONObject o = new JSONObject();
        o.put("error", code);
        return o;
    }
}
