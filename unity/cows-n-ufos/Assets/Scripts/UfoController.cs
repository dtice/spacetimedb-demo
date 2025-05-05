using System;
using System.Collections.Generic;
using SpacetimeDB;
using SpacetimeDB.Types;
using UnityEngine;
using UnityEngine.InputSystem;

public class UfoController : EntityController
{
	public static Color[] ColorPalette = new[]
	{
        //Yellow
		(Color)new Color32(175, 159, 49, 255),
		(Color)new Color32(175, 116, 49, 255),
        
        //Purple
        (Color)new Color32(112, 47, 252, 255),
		(Color)new Color32(51, 91, 252, 255),
        
        //Red
        (Color)new Color32(176, 54, 54, 255),
		(Color)new Color32(176, 109, 54, 255),
		(Color)new Color32(141, 43, 99, 255),
        
        //Blue
        (Color)new Color32(2, 188, 250, 255),
		(Color)new Color32(7, 50, 251, 255),
		(Color)new Color32(2, 28, 146, 255),
	};

    private PlayerController Owner;
    
    [SerializeField]
    private MeshRenderer tractorBeam;
    private InputAction abductAction;

    public void Spawn(Ufo ufo, PlayerController owner)
    {
        base.Spawn(ufo.EntityId);
		// SetColor(ColorPalette[ufo.PlayerId % ColorPalette.Length]);

        Owner = owner;
        GetComponentInChildren<TMPro.TextMeshPro>().text = owner.username;
        abductAction = InputSystem.actions.FindAction("Abduct");
    }

	public override void OnDelete(EventContext context)
	{
		Debug.Log("UfoController: OnDelete");
		base.OnDelete(context);
        Owner.OnUfoDeleted(this);
	}

	public void UfoUpdated(Ufo ufo)
	{
		if (ufo.BeamOn && !tractorBeam.enabled) ShowTractorBeam();
		else if (!ufo.BeamOn && tractorBeam.enabled) HideTractorBeam();
	}

	public void FixedUpdate()
	{
		if (PlayerController.Instance.isLocalPlayer)
		{
			switch (tractorBeam.enabled)
			{
				case true:
					if (!abductAction.IsPressed())
					{
						GameManager.Conn.Reducers.UpdatePlayerBeam(false);
					}
					break;
				case false:
					if (abductAction.IsPressed())
					{
						GameManager.Conn.Reducers.UpdatePlayerBeam(true);
					}
					break;
			}
		}
		else
		{
			// TODO: add network callback to show other players beams
		}
	}

	public void ShowTractorBeam()
	{
		tractorBeam.enabled = true;
	}

	public void HideTractorBeam()
	{
		tractorBeam.enabled = false;
	}
}