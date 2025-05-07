using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class CameraController : MonoBehaviour
{
    public static float WorldSize = 0.0f;

    [Header("Orbit Camera Settings")]
    public float distance = 5.0f;         // Distance from target
    public float xSpeed = 120.0f;         // X rotation speed
    public float ySpeed = 120.0f;         // Y rotation speed
    public float yMinLimit = -20f;        // Minimum Y angle
    public float yMaxLimit = 80f;         // Maximum Y angle
    public float distanceMin = 0.25f;        // Minimum distance
    public float distanceMax = 15f;       // Maximum distance
    public float smoothTime = 0.2f;       // Camera smoothing time
    public bool enableOrbit = true;       // Toggle for orbit controls

    private float x = 0.0f;               // Current X rotation
    private float y = 0.0f;               // Current Y rotation
    private Vector3 targetPosition;       // Position camera is tracking
    private Vector3 currentVelocity;      // For smooth damping

    private void Start()
    {
        Vector3 angles = transform.eulerAngles;
        x = angles.y;
        y = angles.x;
    }

    private void LateUpdate()
    {
        // Calculate the target position
        Vector3 arenaCenterTransform = new Vector3(WorldSize / 2, WorldSize / 2, -10.0f);
        if (PlayerController.Instance == null || !GameManager.IsConnected())
        {
            // Set the camera to be in middle of the arena if we are not connected or 
            // there is no local player
            targetPosition = arenaCenterTransform;
            OrbitalCameraControl(targetPosition);
            return;
        }

        var centerOfMass = PlayerController.Instance.CenterOfMass();
        if (centerOfMass.HasValue)
        {
            // Set the target position to be the center of mass of the local player
            targetPosition = centerOfMass.Value;
            OrbitalCameraControl(targetPosition);
        }
        else
        {
            targetPosition = arenaCenterTransform;
            OrbitalCameraControl(targetPosition);
        }

        float targetCameraSize = CalculateCameraSize(PlayerController.Instance);

        // Only update orthographic size if we're using an orthographic camera
        if (Camera.main.orthographic)
        {
            Camera.main.orthographicSize = Mathf.Lerp(Camera.main.orthographicSize, targetCameraSize, Time.deltaTime * 2);
        }
    }

    private void OrbitalCameraControl(Vector3 targetPos)
    {
        if (enableOrbit)
        {
            // Update rotation based on input if orbit is enabled
            if (Input.GetMouseButton(1)) // Right mouse button
            {
                x += Input.GetAxis("Mouse X") * xSpeed * Time.deltaTime;
                y -= Input.GetAxis("Mouse Y") * ySpeed * Time.deltaTime;

                y = ClampAngle(y, yMinLimit, yMaxLimit);
            }

            // Mouse wheel controls zoom
            distance = Mathf.Clamp(distance - Input.GetAxis("Mouse ScrollWheel") * 5, distanceMin, distanceMax);
        }

        // Calculate rotation and position
        Quaternion rotation = Quaternion.Euler(y, x, 0);
        Vector3 negDistance = new Vector3(0.0f, 0.0f, -distance);
        Vector3 position = rotation * negDistance + targetPos;

        // Apply smoothing to camera movement
        transform.rotation = Quaternion.Slerp(transform.rotation, rotation, Time.deltaTime / smoothTime);
        transform.position = Vector3.SmoothDamp(transform.position, position, ref currentVelocity, smoothTime);

        // Always look at the target
        transform.LookAt(targetPos);
    }

    private float CalculateCameraSize(PlayerController player)
    {
        return 50f + //Base size
            Mathf.Min(50, player.TotalMass() / 5); //Increase camera size with mass
    }

    private float ClampAngle(float angle, float min, float max)
    {
        if (angle < -360f)
            angle += 360f;
        if (angle > 360f)
            angle -= 360f;
        return Mathf.Clamp(angle, min, max);
    }
}