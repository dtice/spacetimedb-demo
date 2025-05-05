using SpacetimeDB.Types;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class PrefabManager : MonoBehaviour
{
	private static PrefabManager Instance;

	public GameObject UfoPrefab;
	public GameObject CowPrefab;
	public GameObject PlayerPrefab;

	private void Awake()
	{
		Instance = this;
	}

	public static UfoController SpawnUfo(Ufo ufo, PlayerController owner)
	{
		var prefab = Instantiate(Instance.UfoPrefab);
		var entityController = prefab.GetComponent<UfoController>();
		entityController.name = $"Ufo - {ufo.EntityId}";
		entityController.Spawn(ufo, owner);
		owner.OnUfoSpawned(entityController);
		return entityController;
	}

	public static CowController SpawnCow(Cow cow)
	{
		var prefab = Instantiate(Instance.CowPrefab);
		var entityController = prefab.GetComponent<CowController>();
		entityController.name = $"Cow - {cow.EntityId}";
		entityController.Spawn(cow);
		return entityController;
	}

	public static PlayerController SpawnPlayer(Player player)
	{
		var prefab = Instantiate(Instance.PlayerPrefab);
		var playerController = prefab.GetComponent<PlayerController>();
		playerController.name = $"PlayerController - {player.Name}";
		playerController.Initialize(player);
		return playerController;
	}
}