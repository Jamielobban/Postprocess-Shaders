using UnityEngine;
using DG.Tweening;

public class AnimateKernelSize : MonoBehaviour
{
    [SerializeField] private Material targetMaterial;
    [SerializeField] private string propertyName = "_KernelSize";
    [SerializeField] private float startValue = 5f;
    [SerializeField] private float endValue = 17f;
    [SerializeField] private float duration = 2f;
    [SerializeField] private float holdTime = 0.5f; // time to stay at max

    private Sequence seq;

    private void Start()
    {
        if (targetMaterial == null)
        {
            Debug.LogError("No material assigned to AnimateKernelSizeOnClick!");
            return;
        }

        targetMaterial.SetFloat(propertyName, startValue);
    }

    private void Update()
    {
        if (Input.GetMouseButtonDown(0))
        {
            StartTween();
        }
    }

    private void StartTween()
    {
        // Kill any existing sequence
        seq?.Kill();

        // Create a sequence for up -> hold -> down
        seq = DOTween.Sequence();

        seq.Append(
            DOTween.To(
                () => targetMaterial.GetFloat(propertyName),
                x => targetMaterial.SetFloat(propertyName, x),
                endValue,
                duration
            ).SetEase(Ease.InOutSine)
        );

        // Hold at max
        seq.AppendInterval(holdTime);

        // Back down
        seq.Append(
            DOTween.To(
                () => targetMaterial.GetFloat(propertyName),
                x => targetMaterial.SetFloat(propertyName, x),
                startValue,
                duration
            ).SetEase(Ease.InOutSine)
        );

        // Loop forever
        seq.SetLoops(-1, LoopType.Restart);

        // Optional rounding if your shader expects int
        seq.OnUpdate(() =>
        {
            float current = Mathf.Round(targetMaterial.GetFloat(propertyName));
            targetMaterial.SetFloat(propertyName, current);
        });
    }
}
