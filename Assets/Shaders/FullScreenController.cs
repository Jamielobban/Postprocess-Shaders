using UnityEngine;
using UnityEngine.InputSystem; // New Input System
using DG.Tweening;

[DisallowMultipleComponent]
public class FullScreenController : MonoBehaviour
{
    [Header("Same material used by the URP Full Screen Pass")]
    public Material mat;

    [Header("Action bound to <Mouse>/rightButton (Button action)")]
    public InputActionReference rightClickAction;

    [Header("Shader property references (exact, case-sensitive)")]
    [SerializeField] string waveProp    = "_WaveLength";
    [SerializeField] string bleedProp   = "_BleedValue";
    [SerializeField] string enabledProp = "_Enabled";

    [Header("Start/Target values")]
    public float baseWave    = 0f;
    public float targetWave  = 50f;
    public float baseBleed   = 0f;
    public float targetBleed = 8.7f;

    [Header("Timing & Curves (per-property)")]
    [Min(0f)] public float waveDuration  = 0.6f;
    public Ease            waveEase      = Ease.InOutSine;
    [Min(0f)] public float bleedDuration = 0.6f;
    public Ease            bleedEase     = Ease.InOutSine;

    [Header("Disable tween (Enabled: 1 → 0)")]
    [Min(0f)] public float enabledDuration = 0.2f;
    public Ease            enabledEase     = Ease.Linear;

    [Tooltip("If true, material starts at base values on Play")]
    public bool startAtBaseOnPlay = true;

    int waveID, bleedID, enabledID;
    Sequence seq;

    void Awake()
    {
        if (!mat)
        {
            Debug.LogError("[Tweener] Assign the Full Screen Pass material.");
            enabled = false;
            return;
        }

        waveID    = Shader.PropertyToID(waveProp);
        bleedID   = Shader.PropertyToID(bleedProp);
        enabledID = Shader.PropertyToID(enabledProp);

        if (!mat.HasProperty(waveID))    Debug.LogError($"[Tweener] '{mat.name}' has no '{waveProp}'.");
        if (!mat.HasProperty(bleedID))   Debug.LogError($"[Tweener] '{mat.name}' has no '{bleedProp}'.");
        if (!mat.HasProperty(enabledID)) Debug.LogWarning($"[Tweener] '{mat.name}' has no '{enabledProp}'. (optional)");
    }

    void Start()
    {
        if (!mat) return;

        if (startAtBaseOnPlay)
        {
            SafeSet(waveID,  baseWave);
            SafeSet(bleedID, baseBleed);
            SafeSet(enabledID, 0f); // start off
        }
    }

    void OnEnable()
    {
        if (rightClickAction == null)
        {
            Debug.LogError("[Tweener] Assign an InputActionReference for right click.");
            return;
        }
        rightClickAction.action.performed += OnRightClick;
        rightClickAction.action.Enable();
    }

    void OnDisable()
    {
        if (seq != null && seq.IsActive()) seq.Kill();
        if (rightClickAction != null)
        {
            rightClickAction.action.performed -= OnRightClick;
            rightClickAction.action.Disable();
        }
    }

    void OnRightClick(InputAction.CallbackContext _)
    {
        if (!mat || !mat.HasProperty(waveID) || !mat.HasProperty(bleedID)) return;

        // If currently animating, kill and restart from base
        if (seq != null && seq.IsActive()) seq.Kill();

        // Prep: set to base and enable effect
        SafeSet(waveID,  baseWave);
        SafeSet(bleedID, baseBleed);
        SafeSet(enabledID, 1f);

        float curWave    = baseWave;
        float curBleed   = baseBleed;
        float curEnabled = 1f; // we'll tween this to 0

        // Independent tweens (own duration + ease each) from base -> target
        Tweener tWave = DOTween
            .To(() => curWave, v => { curWave = v; SafeSet(waveID, v); }, targetWave, waveDuration)
            .SetEase(waveEase);

        Tweener tBleed = DOTween
            .To(() => curBleed, v => { curBleed = v; SafeSet(bleedID, v); }, targetBleed, bleedDuration)
            .SetEase(bleedEase);

        // Enabled tween: AFTER wave/bleed complete, tween Enabled from 1 -> 0
        Tween tEnabledDown = null;
        if (mat.HasProperty(enabledID))
        {
            tEnabledDown = DOTween
                .To(() => curEnabled, v => { curEnabled = v; SafeSet(enabledID, v); }, 0f, enabledDuration)
                .SetEase(enabledEase);
        }

        // Sequence: play wave+bleed together, then enabled tween, then snap back to base
        seq = DOTween.Sequence()
                     .Join(tWave)
                     .Join(tBleed);

        if (tEnabledDown != null)
            seq.Append(tEnabledDown);
        else
            seq.AppendCallback(() => SafeSet(enabledID, 0f)); // fallback if missing prop

        seq.AppendCallback(() =>
        {
            // Reset values to base so the next click always starts from base
            SafeSet(waveID,  baseWave);
            SafeSet(bleedID, baseBleed);
        });
    }

    /// <summary>Programmatic trigger (same as right-click).</summary>
    public void Trigger() => OnRightClick(default);

    /// <summary>Utility: sets float if the property exists.</summary>
    void SafeSet(int id, float value)
    {
        if (mat != null && mat.HasProperty(id))
            mat.SetFloat(id, value);
    }
}
