using System.Collections.Generic;
using System.Linq;
using SpacetimeDB;
using SpacetimeDB.Types;
using UnityEngine;

public class PlayerController : MonoBehaviour
{
    private const int SEND_UPDATES_PER_SEC = 20;
    private const float SEND_UPDATES_FREQUENCY = 1f / SEND_UPDATES_PER_SEC;

    public static PlayerController local { get; private set; }

    public uint playerId;
    private float lastMovementSendTimestamp;
    private Vector2? lockInputPosition;
    private List<UfoController> ownedUfos = new List<UfoController>();

    public string username => GameManager.Conn.Db.Player.PlayerId.Find(playerId)?.Name;
    public int numberOfOwnedUfos => ownedUfos.Count;
    public bool isLocalPlayer => this == local;

    public void Initialize(Player player)
    {
        playerId = player.PlayerId;
        if (player.Identity == GameManager.LocalIdentity)
        {
            local = this;
        }
    }

    public void Update()
    {
        if (!isLocalPlayer || numberOfOwnedUfos == 0)
        {
            return;
        }

        if (Input.GetKeyDown(KeyCode.Q))
        {
            if (lockInputPosition.HasValue)
            {
                lockInputPosition = null;
            }
            else
            {
                lockInputPosition = (Vector2)Input.mousePosition;
            }
        }

        // Throttled input requests
        if (Time.time - lastMovementSendTimestamp >= SEND_UPDATES_FREQUENCY)
        {
            lastMovementSendTimestamp = Time.time;

            var mousePosition = lockInputPosition ?? (Vector2)Input.mousePosition;
            var screenSize = new Vector2
            {
                x = Screen.width,
                y = Screen.height,
            };
            var centerOfScreen = screenSize / 2;

            var direction = (mousePosition - centerOfScreen) / (screenSize.y / 3);
            if (testInputEnabled) { direction = testInput; }
            GameManager.Conn.Reducers.UpdatePlayerInput(new Vector2(0.0f, 0.0f));
            // GameManager.Conn.Reducers.UpdatePlayerInput(direction);
        }
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