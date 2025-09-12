$outputContext.Permissions.Add(
    @{
        displayName    = "ADMIN"
        Identification = @{            
            Reference = "ADMIN"
        }
    }
);
$outputContext.Permissions.Add(
    @{
        displayName    = "TRAINER"
        Identification = @{            
            Reference = "TRAINER"
        }
    }
);
$outputContext.Permissions.Add(
    @{
        displayName    = "PLANNER"
        Identification = @{            
            Reference = "PLANNER"
        }
    }
);
$outputContext.Permissions.Add(
    @{
        displayName    = "MANAGER"
        Identification = @{            
            Reference = "MANAGER"
        }
    }
);
$outputContext.Permissions.Add(
    @{
        displayName    = "TEST"
        Identification = @{
            Reference = "TEST"
        }
    }
);
$outputContext.Permissions.Add(
    @{
        displayName    = "EXTERN"
        Identification = @{
            Reference = "EXTERN"            
        }
    }
);
$outputContext.Permissions.Add(
    @{
        displayName    = "EXTERNAL_TRAINER"
        Identification = @{
            Reference = "EXTERNAL_TRAINER"
        }
    }
);
