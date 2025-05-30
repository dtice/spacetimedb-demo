using System;
using System.Collections.Generic;
using SpacetimeDB;
using SpacetimeDB.Types;
using UnityEngine;

public class GameManager : MonoBehaviour
{
    const string SERVER_URL = "https://spacetime.dilltice.com";
    const string MODULE_NAME = "cows-n-ufos";

    [SerializeField] private GameObject menu;
    
    public static Boolean LockPlayerInput = false;

    public static event Action OnConnected;
    public static event Action OnSubscriptionApplied;

    public float borderThickness = 2;
    public Material borderMaterial;

	public static GameManager Instance { get; private set; }
    public static Identity LocalIdentity { get; private set; }
    public static DbConnection Conn { get; private set; }
    public static DbConnection DB { get; private set; }

    public static Dictionary<uint, EntityController> Entities = new Dictionary<uint, EntityController>();
    public static Dictionary<uint, PlayerController> Players = new Dictionary<uint, PlayerController>();

    private void Start()
    {
        Instance = this;
        menu.SetActive(LockPlayerInput);
        Application.targetFrameRate = 60;

        // In order to build a connection to SpacetimeDB we need to register
        // our callbacks and specify a SpacetimeDB server URI and module name.
        var builder = DbConnection.Builder()
            .OnConnect(HandleConnect)
            .OnConnectError(HandleConnectError)
            .OnDisconnect(HandleDisconnect)
            .WithUri(SERVER_URL)
            .WithModuleName(MODULE_NAME);

        // If the user has a SpacetimeDB auth token stored in the Unity PlayerPrefs,
        // we can use it to authenticate the connection.
        if (AuthToken.Token != "")
        {
        }

        // Building the connection will establish a connection to the SpacetimeDB
        // server.
        Conn = builder.Build();
    }

    private void SetupArena(float worldSize)
    {
        CreateBorderCube(new Vector2(worldSize / 2.0f, worldSize + borderThickness / 2),
            new Vector2(worldSize + borderThickness * 2.0f, borderThickness)); //North
        CreateBorderCube(new Vector2(worldSize / 2.0f, -borderThickness / 2),
            new Vector2(worldSize + borderThickness * 2.0f, borderThickness)); //South
        CreateBorderCube(new Vector2(worldSize + borderThickness / 2, worldSize / 2.0f),
            new Vector2(borderThickness, worldSize + borderThickness * 2.0f)); //East
        CreateBorderCube(new Vector2(-borderThickness / 2, worldSize / 2.0f),
            new Vector2(borderThickness, worldSize + borderThickness * 2.0f)); //West

        CameraController.WorldSize = worldSize;
    }

    private void CreateBorderCube(Vector2 position, Vector2 scale)
    {
        var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
        cube.name = "Border";
        cube.transform.localScale = new Vector3(scale.x, 1, scale.y);
        cube.transform.position = new Vector3(position.x, 0.5f, position.y);
        cube.GetComponent<MeshRenderer>().material = borderMaterial;
    }

    // Called when we connect to SpacetimeDB and receive our client identity
    void HandleConnect(DbConnection conn, Identity identity, string token)
    {
        Debug.Log("Connected.");
        AuthToken.SaveToken(token);
        LocalIdentity = identity;

        conn.Db.Ufo.OnInsert += UfoOnInsert;
        conn.Db.Ufo.OnUpdate += UfoOnUpdate;
        conn.Db.Entity.OnUpdate += EntityOnUpdate;
        conn.Db.Entity.OnDelete += EntityOnDelete;
        conn.Db.Cow.OnInsert += CowOnInsert;
        conn.Db.Cow.OnUpdate += CowOnUpdate;
        conn.Db.Player.OnInsert += PlayerOnInsert;
        conn.Db.Player.OnDelete += PlayerOnDelete;
        DB = conn;

        OnConnected?.Invoke();

        // Request all tables
        Conn.SubscriptionBuilder()
            .OnApplied(HandleSubscriptionApplied)
            .SubscribeToAllTables();
    }

    private static void UfoOnInsert(EventContext context, Ufo insertedValue)
    {
        var player = GetOrCreatePlayer(insertedValue.PlayerId);
        var entityController = PrefabManager.SpawnUfo(insertedValue, player);
        Entities.Add(insertedValue.EntityId, entityController);
    }

    private static void UfoOnUpdate(EventContext context, Ufo oldUfo, Ufo newUfo)
    {
        if (Entities.TryGetValue(newUfo.EntityId, out var entityController))
        {
            (entityController as UfoController)?.UfoUpdated(newUfo);
        }
    }

    private static void EntityOnUpdate(EventContext context, Entity oldEntity, Entity newEntity)
    {
        if (Entities.TryGetValue(newEntity.EntityId, out var entityController))
        {
            entityController.OnEntityUpdated(newEntity);
        }
    }

    private static void EntityOnDelete(EventContext context, Entity oldEntity)
    {
        Debug.Log("GameManager: EntityOnDelete");
        if (Entities.Remove(oldEntity.EntityId, out var entityController))
        {
            Debug.Log("GameManager: Removed entity");
            entityController.OnDelete(context);
        }
    }

    private static void CowOnInsert(EventContext context, Cow insertedValue)
    {
        var entityController = PrefabManager.SpawnCow(insertedValue);
        Debug.Log("ADDING COW: " + entityController.name);
        Entities.Add(insertedValue.EntityId, entityController);
        Debug.Log("ID: " + Entities[insertedValue.EntityId].EntityId);
    }

    private static void CowOnUpdate(EventContext context, Cow oldCow, Cow newCow)
    {
        if (Entities.TryGetValue(newCow.EntityId, out var entityController))
        {
            (entityController as CowController)?.OnCowUpdated(context, oldCow, newCow);
        }
    }

    private static void PlayerOnInsert(EventContext context, Player insertedPlayer)
    {
        GetOrCreatePlayer(insertedPlayer.PlayerId);
    }

    private static void PlayerOnDelete(EventContext context, Player deletedvalue)
    {
        if (Players.Remove(deletedvalue.PlayerId, out var playerController))
        {
            GameObject.Destroy(playerController.gameObject);
        }
    }

    private static PlayerController GetOrCreatePlayer(uint playerId)
    {
        if (!Players.TryGetValue(playerId, out var playerController))
        {
            var player = Conn.Db.Player.PlayerId.Find(playerId);
            playerController = PrefabManager.SpawnPlayer(player);
            Players.Add(playerId, playerController);
        }

        return playerController;
    }

    void HandleConnectError(Exception ex)
    {
        Debug.LogError($"Connection error: {ex}");
    }

    void HandleDisconnect(DbConnection _conn, Exception ex)
    {
        Debug.Log("Disconnected.");
        if (ex != null)
        {
            Debug.LogException(ex);
        }
    }

    private void HandleSubscriptionApplied(SubscriptionEventContext ctx)
    {
        Debug.Log("Subscription applied!");
        OnSubscriptionApplied?.Invoke();

        var worldSize = Conn.Db.Config.Id.Find(0).WorldSize;
        SetupArena(worldSize);

        ctx.Reducers.EnterGame(PlayerPrefs.GetString("PlayerName") ?? "Dingus");
    }

    public static bool IsConnected()
    {
        return Conn != null && Conn.IsActive;
    }

    public void Disconnect()
    {
        Conn.Disconnect();
        Conn = null;
    }

    public void ToggleMenu()
    {
        LockPlayerInput = !LockPlayerInput;
        menu.SetActive(LockPlayerInput);
    }
}