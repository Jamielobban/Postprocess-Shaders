using UnityEngine;
using UnityEngine.InputSystem; // New Input System
using DG.Tweening;

public class FullScreenController : MonoBehaviour
{
    [Header("Same material used by the URP Full Screen Pass")]
    public Material mat;

    [Header("Action bound to <Mouse>/rightButton (Button action)")]
    public InputActionReference rightClickAction;

    [Header("Shader property references (exact, case-sensitive)")]
    [SerializeField] string waveProp  = "_WaveLength";
    [SerializeField] string bleedProp = "_BleedValue";

    [Header("Start/Target values")]
    public float baseWave   = 0f;
    public float targetWave = 50f;
    public float baseBleed  = 0f;
    public float targetBleed= 8.7f; // set what you want

    [Header("Timing & Curve")]
    [Min(0f)] public float duration = 0.6f;
    public Ease ease = Ease.InOutSine;
    public bool startAtBaseOnPlay = true;

    [Header("Click behavior")]
    [Tooltip("If ON: each right-click flips between base and target. If OFF: every click goes to target.")]
    public bool toggleOnClick = true;

    int waveID, bleedID;
    bool isAtTarget;
    Sequence seq;

    void Awake()
    {
        if (!mat) { Debug.LogError("[Tweener] Assign the Full Screen Pass material."); enabled = false; return; }
        waveID  = Shader.PropertyToID(waveProp);
        bleedID = Shader.PropertyToID(bleedProp);

        if (!mat.HasProperty(waveID))  Debug.LogError($"[Tweener] '{mat.name}' has no '{waveProp}'.");
        if (!mat.HasProperty(bleedID)) Debug.LogError($"[Tweener] '{mat.name}' has no '{bleedProp}'.");
    }

    void Start()
    {
        if (startAtBaseOnPlay && mat)
        {
            if (mat.HasProperty(waveID))  mat.SetFloat(waveID,  baseWave);
            if (mat.HasProperty(bleedID)) mat.SetFloat(bleedID, baseBleed);
            isAtTarget = false;
        }
    }

    void OnEnable()
    {
        if (rightClickAction == null) { Debug.LogError("[Tweener] Assign an InputActionReference for right click."); return; }
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
        if (seq != null && seq.IsActive()) seq.Kill();

        float curWave  = mat.GetFloat(waveID);
        float curBleed = mat.GetFloat(bleedID);

        // Decide where to go
        bool goToTarget = toggleOnClick ? !isAtTarget : true;
        float toWave    = goToTarget ? targetWave  : baseWave;
        float toBleed   = goToTarget ? targetBleed : baseBleed;

        // Build tweens
        Tweener tWave  = DOTween.To(() => curWave,  v => { curWave  = v; mat.SetFloat(waveID,  v); }, toWave,  duration).SetEase(ease);
        Tweener tBleed = DOTween.To(() => curBleed, v => { curBleed = v; mat.SetFloat(bleedID, v); }, toBleed, duration).SetEase(ease);

        seq = DOTween.Sequence().Join(tWave).Join(tBleed).OnComplete(() => { if (toggleOnClick) isAtTarget = goToTarget; });
    }
}