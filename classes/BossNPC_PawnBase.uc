class BossNPC_PawnBase extends Pawn implements (IBossNpcPawn);

var PrivateWrite SkeletalMeshComponent 		      m_BodyMesh;
var PrivateWrite DynamicLightEnvironmentComponent m_MeshLighEnv;

var PrivateWrite AnimNodeBlend    m_CustomAnimBlend;
var PrivateWrite AnimNodeSequence m_CustomAnimSequence;
var private name m_CustomAnimSeqName;
var private repnotify int  m_CustomAnimSeqPlayID;

var float m_Speed;

var bool  m_IsSprinting;
var float m_SprintSpeed;

var bool  m_IsInCombat;
var float m_CombatSpeed;

var float    m_FootStepStartDist;
var SoundCue m_FootStepSounds;

var float    m_FarFootStepStartDist;
var float    m_FarFootStepEndDist;
var SoundCue m_FarFootStepSounds;

var private int m_FootStep;
var private int m_FarFootStep;

var repnotify bool m_dying;
var bool m_rotateToGround;
var ParticleSystemComponent deathDust;

`include(Stocks)
`include(Log)

replication
{
	if (bNetDirty && Role == ROLE_Authority)
		m_Speed, m_IsSprinting, m_SprintSpeed, m_IsInCombat, m_CustomAnimSeqName, m_CustomAnimSeqPlayID, m_dying;
}

simulated event PostInitAnimTree(SkeletalMeshComponent SkelComp) {
    super.PostInitAnimTree(SkelComp);

    m_CustomAnimBlend = AnimNodeBlend(m_BodyMesh.FindAnimNode('CustomAnim_Blend'));
    m_CustomAnimSequence = AnimNodeSequence(m_BodyMesh.FindAnimNode('CustomAnim_Sequence'));
    m_CustomAnimSequence.bCauseActorAnimEnd = true;
}

simulated event ReplicatedEvent(name VarName)
{
	if (VarName == 'm_CustomAnimSeqPlayID')
	{
		self.PlayCustomAnim(m_CustomAnimSeqName);
	}
	else if(VarName == 'm_dying') {
		GotoState('Dying');
	}

    super.ReplicatedEvent(VarName);
}

simulated function float GetMoveSpeed()
{
	return m_IsSprinting ? m_SprintSpeed : (m_IsInCombat ? m_CombatSpeed : m_Speed);
}

simulated event Tick(float DeltaTime) {
	local float speed;
	local Rotator newRotation;

	if(m_rotateToGround) {
		self.AirSpeed    = 0;
    	self.GroundSpeed = 0;
    	velocity = vec3(0,0,0);
		newRotation = Rotation;
		newRotation.Pitch -= 3000 * DeltaTime;
		SetRotation( newRotation );

 		return;
	}

	speed = self.GetMoveSpeed();
    self.AirSpeed    = speed;
    self.GroundSpeed = speed;

    super.Tick(DeltaTime);
}

simulated function PlayCustomAnim(name SeqName)
{
	m_CustomAnimBlend.SetBlendTarget(1.0, 0.5);
    m_CustomAnimSequence.SetAnim(SeqName);
    m_CustomAnimSequence.PlayAnim();

    if (self.Role == ROLE_Authority)
    {
        m_CustomAnimSeqName = SeqName;
        m_CustomAnimSeqPlayID++;
    }
}

simulated event OnAnimEnd(AnimNodeSequence SeqNode, float PlayedTime, float ExcessTime)
{
    super.OnAnimEnd(SeqNode, PlayedTime, ExcessTime);

    if (SeqNode == m_CustomAnimSequence) {
        m_CustomAnimBlend.SetBlendTarget(0, 0.2);
    }

}

simulated event PlayFootStepSound(int FootDown)
{
	local PlayerController PC;
	local float dist;

	super.PlayFootStepSound(FootDown);

    foreach class'WorldInfo'.static.GetWorldInfo().LocalPlayerControllers(class'PlayerController', PC)
    {
        dist = VSize2D(PC.Pawn.Location - self.Location);

        if (dist >= m_FarFootStepStartDist)
        {
            if (dist > m_FarFootStepEndDist)
                continue;

        	PC.PlaySound(m_FarFootStepSounds, true,,, self.Location);
        }
        else
        {
        	PC.PlaySound(m_FootStepSounds, true,,, self.Location);
        }
    }
}

function gibbedBy(actor Other) { }

simulated function bool Died(Controller Killer, class<DamageType> DamageType, vector HitLocation) {
	BossNPC_AIBase(self.Controller).PawnDiedEvent(Killer, DamageType);
	GotoState('Dying');

	return true;
}

simulated function _Dead() {
	deathDust.deactivateSystem();
    self.Destroy();
}

simulated state Dying {

	simulated function pawnFadeOut() {
	    local Vector BoneLoc;

		BoneLoc = m_BodyMesh.GetBoneLocation('joint7');
	    deathDust = WorldInfo.MyEmitterPool.SpawnEmitter(ParticleSystem'CHV_PartiPack.Particles.P_smokepot',BoneLoc - vec3(0,0,250));
	    deathDust.setscale( 2 );
	}

Begin:
	m_dying = true;
	SetTimer(6.0, false, '_Dead');
	pawnFadeOut();
    PlayCustomAnim('Die');
	FinishAnim(m_CustomAnimSequence);
	m_rotateToGround = true;
    m_CustomAnimSequence.stopAnim();
    AnimTree(mesh.Animations).SetUseSavedPose(TRUE);
	Mesh.PhysicsWeight = 999.0;
	SetPhysics(PHYS_None);

    //InitRagdoll(); <-- not working too well, makes cyclops deflate like a baloon
}

function playHitSound(AocPawn InstigatedBy) {
	local SoundCue ImpactSound;
	local AOCMeleeWeapon MeleeOwnerWeapon;

	MeleeOwnerWeapon = AOCMeleeWeapon(InstigatedBy.Weapon);
	ImpactSound = MeleeOwnerWeapon.ImpactSounds[AocWeapon(InstigatedBy.Weapon).AOCWepAttachment.LastSwingType].Light;
	if(ImpactSound != none) {
		InstigatedBy.StopWeaponSounds();
		InstigatedBy.PlayServerSoundWeapon( ImpactSound );
	}
}

function bool FindNearestBone(vector InitialHitLocation, out name BestBone, out vector BestHitLocation) {
	local int i, dist, BestDist;
	local vector BoneLoc;
	local name BoneName;

	if (Mesh.PhysicsAsset != none) {
		for (i=0;i<Mesh.PhysicsAsset.BodySetup.Length;i++) {
			BoneName = Mesh.PhysicsAsset.BodySetup[i].BoneName;
			// If name is not empty and bone exists in this mesh
			if ( BoneName != '' && Mesh.MatchRefBone(BoneName) != INDEX_NONE) {
				BoneLoc = Mesh.GetBoneLocation(BoneName);
				Dist = VSize(InitialHitLocation - BoneLoc);
				if ( i==0 || Dist < BestDist ) {
					BestDist = Dist;
					BestBone = Mesh.PhysicsAsset.BodySetup[i].BoneName;
					BestHitLocation = BoneLoc;
				}
			}
		}

		if (BestBone != '') {
			return true;
		}
	}
	return false;
}

function String GetNotifyKilledHudMarkupText() {
	return "<font color=\"#B27500\">Boss NPC</font>";
}

defaultproperties
{
    ControllerClass = class'BossNPC_AIBase'

    bBounce               = false
    bReplicateHealthToAll = true
    bCanBeBaseForPawns    = false
    bCanStepUpOn          = false

    begin object name=MeshLightEnvironment class=DynamicLightEnvironmentComponent
        bSynthesizeSHLight              = true
        bIsCharacterLightEnvironment    = true
        bUseBooleanEnvironmentShadowing = false

        InvisibleUpdateTime       = 1
        MinTimeBetweenFullUpdates = .2
    end object
    Components.Add(MeshLightEnvironment)

    m_MeshLighEnv = MeshLightEnvironment

    begin object name=BodyMesh class=SkeletalMeshComponent
        AlwaysLoadOnClient = true
        AlwaysLoadOnServer = true

	    bUpdateSkelWhenNotRendered        = true
	    bIgnoreControllersWhenNotRendered = false

        CastShadow         = true
        bCastDynamicShadow = true

        bCacheAnimSequenceNodes = false

        CollideActors      = false
        BlockActors        = false
        BlockZeroExtent    = false
        BlockNonZeroExtent = false

        RBChannel             = RBCC_Untitled3
        RBCollideWithChannels = ( Untitled3 = true )
        RBDominanceGroup      = 20

        LightEnvironment = MeshLightEnvironment

        bHasPhysicsAssetInstance = true

        TickGroup = TG_PreAsyncWork

        bPerBoneMotionBlur = true
    end object
    Components.Add(BodyMesh)

    m_BodyMesh = BodyMesh
    Mesh = BodyMesh

    begin object name=CollisionCylinder
        CollideActors      = true
        BlockActors        = true
        BlockRigidBody     = true
        BlockZeroExtent    = true
        BlockNonZeroExtent = true
    end object

    CollisionComponent = CollisionCylinder
    WalkingPhysics     = PHYS_Walking

    m_FootStepStartDist = 0
    m_FarFootStepStartDist = 300
    m_FarFootStepEndDist = 600

    m_CustomAnimSeqPlayID = 0
}
