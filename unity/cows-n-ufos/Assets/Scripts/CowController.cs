using SpacetimeDB.Types;
using UnityEngine;

public class CowController : EntityController
{
    public Vector3 direction = Vector3.back;
    public static Color[] ColorPalette = new[]
    {
        (Color)new Color32(119, 252, 173, 255),
        (Color)new Color32(76, 250, 146, 255),
        (Color)new Color32(35,  246, 120, 255),

        (Color)new Color32(119, 251, 201, 255),
        (Color)new Color32(76, 249, 184, 255),
        (Color)new Color32(35, 245, 165, 255),
    };
    public void Spawn(Cow cow)
    {
        base.Spawn(cow.EntityId);
        // SetColor(ColorPalette[EntityId % ColorPalette.Length]);
    }

    public void OnCowUpdated(EventContext context, Cow oldCow, Cow newCow)
    {
        direction = new Vector3(
            newCow.Direction.X * 100,
            0,
            newCow.Direction.Z * 100
        );
        
        // Debug.Log("Looking at: " + direction);
        GetComponentInParent<Transform>().LookAt(direction);
    }

    public void OnDrawGizmos()
    {
        Gizmos.color = Color.red;
        Gizmos.DrawLine(transform.position, direction);
    }
}
