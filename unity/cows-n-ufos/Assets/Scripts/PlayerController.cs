using System.Collections.Generic;
using System.Linq;
using SpacetimeDB;
using SpacetimeDB.Types;
using UnityEngine;
using UnityEngine.InputSystem;

public class PlayerController : MonoBehaviour
{
    private const int SEND_UPDATES_PER_SEC = 20;
    private const float SEND_UPDATES_FREQUENCY = 1f / SEND_UPDATES_PER_SEC;

    private GameObject menu;

    public static PlayerController Instance { get; private set; }

    public uint playerId;
    private float lastMovementSendTimestamp;
    private Vector2? lockInputPosition;
    private List<UfoController> ownedUfos = new List<UfoController>();

    public string username => GameManager.Conn.Db.Player.PlayerId.Find(playerId)?.Name;
    public int numberOfOwnedUfos => ownedUfos.Count;
    public bool isLocalPlayer => this == Instance;

    private InputAction moveAction;
    private InputAction abductAction;

    public void Initialize(Player player)
    {
        playerId = player.PlayerId;
        if (player.Identity == GameManager.LocalIdentity)
        {
            Instance = this;
        }

        moveAction = InputSystem.actions.FindAction("Move");
        abductAction = InputSystem.actions.FindAction("Abduct");
        moveAction.Enable();
        abductAction.Enable();
    }

    public void Update()
    {
        if (!isLocalPlayer || numberOfOwnedUfos == 0 || GameManager.LockPlayerInput) return;

        if (Input.GetKeyDown(KeyCode.Escape))
        {
            Debug.Log("Escape");
            GameManager.Instance.ToggleMenu();
        }

        if (Input.GetKeyDown(KeyCode.Q))
        {
            Debug.Log("Q pressed");
            if (lockInputPosition.HasValue)
            {
                lockInputPosition = null;
            }
            else
            {
                lockInputPosition = (Vector2)Input.mousePosition;
            }
        }

        // Movement
        if (!(Time.time - lastMovementSendTimestamp >= SEND_UPDATES_FREQUENCY)) return;

        var rawMoveValue = moveAction.ReadValue<Vector2>();

        // Calculate camera-relative movement
        Vector2 cameraRelativeMoveValue = CalculateCameraRelativeMovement(rawMoveValue);

        // Send the camera-relative movement to the server
        GameManager.Conn.Reducers.UpdatePlayerInput(cameraRelativeMoveValue);

        lastMovementSendTimestamp = Time.time;
    }

    private Vector2 CalculateCameraRelativeMovement(Vector2 inputValue)
    {
        // No movement input, return zero
        if (inputValue.magnitude < 0.1f)
            return Vector2.zero;

        // Get the camera's forward and right vectors
        Camera mainCamera = Camera.main;
        if (mainCamera == null)
            return inputValue; // Fallback to raw input if no camera

        // Get the camera's forward and right vectors, ignoring y (up/down) component
        Vector3 forward = mainCamera.transform.forward;
        forward.y = 0;
        forward.Normalize();

        Vector3 right = mainCamera.transform.right;
        right.y = 0;
        right.Normalize();

        // Calculate the movement direction based on camera orientation
        Vector3 moveDirection = (forward * inputValue.y + right * inputValue.x).normalized;

        // Convert to Vector2 (assuming your game uses x,z plane for movement)
        return new Vector2(moveDirection.x, moveDirection.z);
    }

    private void OnDestroy()
    {
        // If we have any ufos, destroy them
        foreach (var ufo in ownedUfos)
        {
            if (ufo != null)
            {
                Destroy(ufo.gameObject);
            }
        }
        ownedUfos.Clear();
    }

    public void OnUfoSpawned(UfoController ufo)
    {
        ownedUfos.Add(ufo);
    }

    public void OnUfoDeleted(UfoController deletedUfo)
    {
        // This means we got eaten
        if (ownedUfos.Remove(deletedUfo) && isLocalPlayer && ownedUfos.Count == 0)
        {
            // DeathScreen.Instance.SetVisible(true);
        }
    }

    public uint TotalMass()
    {
        return (uint)ownedUfos
            .Select(ufo => GameManager.Conn.Db.Entity.EntityId.Find(ufo.EntityId))
            .Sum(e => e?.Mass ?? 0); //If this entity is being deleted on the same frame that we're moving, we can have a null entity here.
    }

    public Vector3? CenterOfMass()
    {
        if (ownedUfos.Count == 0)
        {
            return null;
        }

        Vector3 totalPos = Vector3.zero;
        float totalMass = 0;
        foreach (var ufo in ownedUfos)
        {
            var entity = GameManager.Conn.Db.Entity.EntityId.Find(ufo.EntityId);
            var position = ufo.transform.position;
            totalPos += (Vector3)position * entity.Mass;
            totalMass += entity.Mass;
        }

        return totalPos / totalMass;
    }

    private void OnGUI()
    {
        if (!isLocalPlayer || !GameManager.IsConnected())
        {
            return;
        }

        GUI.Label(new Rect(0, 0, 100, 50), $"Total Mass: {TotalMass()}");
    }

    //Automated testing members
    private bool testInputEnabled;
    private Vector2 testInput;

    public void SetTestInput(Vector2 input) => testInput = input;
    public void EnableTestInput() => testInputEnabled = true;
}