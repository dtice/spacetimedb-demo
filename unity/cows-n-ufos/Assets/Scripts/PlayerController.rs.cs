using System.Collections.Generic;
using System.Linq;
using SpacetimeDB;
using SpacetimeDB.Types;
using UnityEngine;

public class PlayerController : MonoBehaviour
{
	const int SEND_UPDATES_PER_SEC = 20;
	const float SEND_UPDATES_FREQUENCY = 1f / SEND_UPDATES_PER_SEC;

    public static PlayerController Local { get; private set; }

	private uint PlayerId;
    private float LastMovementSendTimestamp;
    private Vector2? LockInputPosition;
	private List<UfoController> OwnedUfos = new List<UfoController>();

	public string Username => GameManager.Conn.Db.Player.PlayerId.Find(PlayerId).Name;
	public int NumberOfOwnedUfos => OwnedUfos.Count;
	public bool IsLocalPlayer => this == Local;

	public void Initialize(Player player)
    {
        PlayerId = player.PlayerId;
        if (player.Identity == GameManager.LocalIdentity)
        {
            Local = this;
        }
	}

    private void OnDestroy()
    {
        // If we have any ufos, destroy them
        foreach (var ufo in OwnedUfos)
        {
            if (ufo != null)
            {
                Destroy(ufo.gameObject);
            }
        }
        OwnedUfos.Clear();
    }

    public void OnUfoSpawned(UfoController ufo)
    {
        OwnedUfos.Add(ufo);
    }

    public void OnUfoDeleted(UfoController deletedUfo)
	{
		// This means we got eaten
		if (OwnedUfos.Remove(deletedUfo) && IsLocalPlayer && OwnedUfos.Count == 0)
		{
			// DeathScreen.Instance.SetVisible(true);
		}
	}

	public uint TotalMass()
    {
        return (uint)OwnedUfos
            .Select(ufo => GameManager.Conn.Db.Entity.EntityId.Find(ufo.EntityId))
			.Sum(e => e?.Mass ?? 0); //If this entity is being deleted on the same frame that we're moving, we can have a null entity here.
	}

    public Vector2? CenterOfMass()
    {
        if (OwnedUfos.Count == 0)
        {
            return null;
        }
        
        Vector2 totalPos = Vector2.zero;
        float totalMass = 0;
        foreach (var ufo in OwnedUfos)
        {
            var entity = GameManager.Conn.Db.Entity.EntityId.Find(ufo.EntityId);
            var position = ufo.transform.position;
            totalPos += (Vector2)position * entity.Mass;
            totalMass += entity.Mass;
        }

        return totalPos / totalMass;
	}

	private void OnGUI()
	{
		if (!IsLocalPlayer || !GameManager.IsConnected())
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