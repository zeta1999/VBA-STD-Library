VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "stdCallback"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = True
'TODO:
'* Full implementation of Pointer
'* Full implementation of Lambda (Will likely require stdVBAExpression library)
'* StdRun
'* CallCallback module function calling - is there a better way than application.run?

'OBJECT TESTING:
'   Sub main()
'     Dim cb As stdCallback
'     Set cb = stdCallback.Create("Object", Me, "f")
'
'     Dim x As Variant
'     Set x = cb()
'     Debug.Print x.Count
'
'     '---------------------------------------
'
'     Dim cbv As stdCallback
'     Set cbv = stdCallback.Create("Object", Me, "g")
'
'     Dim v As Variant
'     v = cbv()
'     Debug.Print v
'   End Sub
'
'   Function f() As Variant
'     Set f = New Collection
'   End Function
'   Function g() As Variant
'     g = 101
'   End Function
'
'MODULE TESTING:
'   Sub main()
'     Dim cb As stdCallback
'     Set cb = stdCallback.Create("Module", "MyModuleName", "f")
'
'     Dim x As Variant
'     Set x = cb()
'     Debug.Print x.Count
'
'     '---------------------------------------
'
'     Dim cbv As stdCallback
'     Set cbv = stdCallback.Create("Module", "MyModuleName", "g")
'
'     Dim v As Variant
'     v = cbv()
'     Debug.Print v
'   End Sub
'
'   Function f() As Variant
'     Set f = New Collection
'   End Function
'   Function g() As Variant
'     g = 101
'   End Function



'FYI
'Const DISPID_UNKNOWN     = -1
'Const DISPID_VALUE       = 0
'Const DISPID_PROPERTYPUT = -3
'Const DISPID_NEWENUM     = -4
'Const DISPID_EVALUATE    = -5
'Const DISPID_CONSTRUCTOR = -6
'Const DISPID_DESTRUCTOR  = -7
'Const DISPID_COLLECT     = -8

'TODO:
'* Implementation of Pointer
'* CreateLambda()
'* stdCallback.CreateFromAddress(AddressOf Main.Podrick)

'TODO: Lambda Expressions:
'******************
'Callback.[(a,b,c) => a + b * c].Call(1,2,3) ' ==> 7
'Callback.[obj => obj.id].Call(row)  ' ==> row.id


'Direct call convention of VBA.CallByName
#If VBA6 Then
  Private Declare PtrSafe Function rtcCallByName Lib "msvbvm60" (ByRef vRet As Variant, ByVal cObj As Object, ByVal sMethod As LongPtr, ByVal eCallType As VbCallType, ByRef pArgs() As Variant, ByVal lcid As Long) As Long
  Private Declare PtrSafe Sub VariantCopy Lib "oleaut32.dll" (ByRef pvargDest As Variant, ByRef pvargSrc As Variant)
#Else
  Private Declare Function rtcCallByName Lib "msvbvm60" (ByRef vRet As Variant, ByVal cObj As Object, ByVal sMethod As LongPtr, ByVal eCallType As VbCallType, ByRef pArgs() As Variant, ByVal lcid As Long) As Long
  Private Declare Sub VariantCopy Lib "oleaut32.dll" (ByRef pvargDest As Variant, ByRef pvargSrc As Variant)
#End If

Dim pInitialised As Boolean
' Dim pCallback As Collection
' Dim pCompiledLambda As Collection
' Dim pLambdaData As Collection

Private Enum ParentType
  Module = 1
  Object = 2
  Formula = 3
End Enum
Private Type CallbackStruct
  iType as ParentType
  sModuleName as string
  oObject as object
  sMethodName as string
  iCallType as VbCallType
  sFormula as string
End Type
Private pCallback as CallbackStruct

Public Event BeforeRun(ByRef callback as stdCallback, ByRef args as variant)
Public Event AfterRun(ByRef callback as stdCallback, ByRef sResult as variant)



'Create a callback object from module type string, translate to enum and initialise callback
Public Function Create(mType As String, Parent As Variant, Name As String, Optional cType As Integer = VbCallType.VbMethod) As stdCallback
Attribute Create.VB_Description = "Creates an instance of this class."
  Dim iType as ParentType
  if mType = "Module" then
    iType = ParentType.Module
  elseif mType = "Object" then
    iType = ParentType.Object
  else
    CriticalRaise  "Incorrect module type supplied"
  end if
  
  Set Create = New stdCallback
  Call Create.Init(itype, cType, Parent, Name)
  
End Function

'Create callback from Module function directly
Public Function CreateFromModule(ByVal sParentName as string, ByVal sMethodName as string) as stdCallback
Attribute CreateFromModule.VB_Description = "Create callback from module method."
  Set CreateFromModule = New stdCallback
  Call CreateFromModule.Init(ParentType.Module, sParentName, sMethodName)
End Function

'Create callback from object and method name
Public Function CreateFromObjectMethod(ByRef object as object, ByVal sMethodName as string) as stdCallback
Attribute CreateFromObjectMethod.VB_Description = "Create callback from object method."
  Set CreateFromObjectMethod = new stdCallback
  Call CreateFromObjectMethod.Init(ParentType.Object, object, sMethodName, VbCallType.VbMethod)
End Function

'Create callback from object and property name
Public Function CreateFromObjectProperty(ByRef object as object, ByVal sPropName as string, ByVal cType as VbCallType) as stdCallback
Attribute CreateFromObjectProperty.VB_Description = "Create callback from object property."
  Set CreateFromObjectProperty = new stdCallback
  Call CreateFromObjectProperty.Init(ParentType.Object, object, sPropName, cType)
End Function

'CreateEvaluator from 
Public Function CreateEvaluator(ByVal sFormula as string, Optional ByRef evalFunc as stdCallback = nothing) as stdCallback
Attribute CreateEvaluator.VB_Description = "Create callback from Excel formula. This method is VBA Only"
  if Application.Name = "Microsoft Excel" then
    set CreateEvaluator = new stdCallback
    Call CreateEvaluator.Init(ParentType.Formula, sFormula, evalFunc)
  Else
    CriticalRaise "Can only create evaluators in Excel as they rely on Application.Evaluate()"
  end if
End Function

Friend Sub Init(iParentType As Long, ParamArray params() as variant) 'Parent As Variant, Name As String
Attribute Init.VB_Description = "Initialises this object. This should not be called directly unless building a ctor routine e.g. Create()."
  If Not pInitialised Then
    Select Case iParentType
      Case ParentType.Module
        pCallback.iType = iParentType
        pCallback.sModuleName = params(0)
        pCallback.sMethodName = params(1)
      Case ParentType.Object
        pCallback.iType = iParentType
        set pCallback.oObject = params(0)
        pCallback.sMethodName = params(1)
        pCallback.iCallType = params(2)
      Case ParentType.Formula
        pCallback.iType = iParentType
        pCallback.sFormula = params(0)
        set pCallback.oObject = params(1)
      Case Else
        CriticalRaise "Invalid module type submitted"    
    End Select
  Else
    CriticalRaise "Class is already initialised"
  End If
  pInitialised = True
End Sub

'Default Property:
Public Function Run(ParamArray args() As Variant) As Variant
Attribute Run.VB_Description = "Runs the specified callback."
Attribute Run.VB_UserMemId = 0
  If pInitialised And pCallback.iType Then
    'store args as different array otherwise crash occurs
    Dim vArr() As Variant
    vArr = args
    
    'Raise event for listeners
    RaiseEvent BeforeRun(Me, vArr)
    
    'Select procedure based on parent type, as each requires different call conventions
    Dim vRet As Variant
    Select Case pCallback.iType
      Case ParentType.Module
        'TODO: Investigate whether we can call these directly via GetModuleHandleA(), GetProcAddress() and CallWindowProcW()
        'Get currentLength
        Dim currentLength As Integer
        currentLength = UBound(vArr) - LBound(vArr) + 1
        
        'Preserve array but make it 29 args long
        ReDim Preserve vArr(0 To 29)
        
        'Loop over args and bind missing to args not present in initial array
        Dim i As Integer
        For i = 0 To 29
          If i > currentLength - 1 Then
            vArr(i) = GetMissing
          End If
        Next
        
        'Copy results of Application.Run into vRet
        VariantCopy vRet, Application.Run( _
            pCallback.sModuleName & "." & pCallback.sMethodName, _
            vArr(0), vArr(1), _
            vArr(2), vArr(3), _
            vArr(4), vArr(5), _
            vArr(6), vArr(7), _
            vArr(8), vArr(9), _
            vArr(10), vArr(11), _
            vArr(12), vArr(13), _
            vArr(14), vArr(15), _
            vArr(16), vArr(17), _
            vArr(18), vArr(19), _
            vArr(20), vArr(21), _
            vArr(22), vArr(23), _
            vArr(24), vArr(25), _
            vArr(26), vArr(27), _
            vArr(28), vArr(29))
      Case ParentType.object
        'Call function directly
        'Use rtcCallByName to avoid type errors from argument array
        'Src: http://www.vbforums.com/showthread.php?866039-RESOLVED-Store-CallByName-Arguments-list
        
        'Call rtcCallByName
        Dim hr As Long
        hr = rtcCallByName(vRet, pCallback.oObject, StrPtr(pCallback.sMethodName), pCallback.iCallType, vArr, &H409)
        
        'If error then raise
        If hr < 0 Then
          CriticalRaise "Error in rtcCallByName. Error number: " & hr
        End If
      Case ParentType.Formula
        'Yes this is obscenely hacky, but here it goes anyway. The objective is to create an evaluatable formula. This will simply be done by:
        '1) Loop through all arguments and replace $index with the serialized value
        '2) Evaluate with Application.Evaluate (or with evalFunc)
        Dim sEqn As String: sEqn = pCallback.sFormula
        For i = 0 To UBound(vArr)
          If InStr(1, sEqn, "$") Then
            If InStr(1, sEqn, "$" & (i + 1)) Then sEqn = Replace(sEqn, "$" & (i + 1), Serialize(vArr(i)))
          Else
            Exit For
          End If
        Next

        'If evalFunc provided then evaluate with evalFunc, else use Application.Evaluate()
        If pCallback.oObject Is Nothing Then
          VariantCopy vRet, Application.Evaluate(sEqn)
        Else
          VariantCopy vRet, pCallback.oObject.Run(sEqn)
        End If
      Case Else
        CriticalRaise "Cannot call callback. Invalid parent type assigned (" & iParentType & ")."
      End Select

      
      'Allow events to modify result prior to submitting to return
      RaiseEvent AfterRun(Me, vRet)
      
      'Return result
      VariantCopy Run, vRet
  Else
    CriticalRaise "No callback specified. Please initialise with a Create function."
  End If
End Function





Private Function Serialize(data As Variant) As String
  Select Case TypeName(data)
    Case "Integer", "Double", "Float", "Date"
      Serialize = CDbl(data)
    Case "String"
      Serialize = """" & data & """"
    Case Else
      if VarType(data) = vbObject then
        'allows for stuff like --> CreateEvaluator("@(@(@($1,""Workbooks""),""Item"",1),""Name"")")(Application)
        'Assuming @() calls 
        Serialize = ObjPtr(data)
      else
        Serialize = data
      end if
  End Select
End Function

Private Sub CriticalRaise(ByVal sMessage as string)
  'If stdError exists
    if vartype(stdError) then
      Call stdError.Raise("Can only create evaluators in Excel as they rely on Application.Evaluate()")
    Else
      Call Err.Raise(1,"stdCallback", sMessage)
    End If
    End
End Sub

Private Function GetMissing(Optional arg As Variant) As Variant
  GetMissing = arg
End Function