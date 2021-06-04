[#ftl strict_vars=true]
[#--
/* Copyright (c) 2021 Jonathan Revusky, revusky@javacc.com
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright notices,
 *       this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name Jonathan Revusky, Sun Microsystems, Inc.
 *       nor the names of any contributors may be used to endorse 
 *       or promote products derived from this software without specific prior written 
 *       permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */
 --]

 [#--
    This template handles the generation of a class that is a holder
    for all the static data that represents an NFA state machine
 --]

[#var NFA_RANGE_THRESHOLD = 16]
[#var MAX_INT=2147483647]
[#var multipleLexicalStates = grammar.lexerData.lexicalStates.size()>1]

 /* Generated by: ${generated_by}. ${filename} */
 
[#if grammar.parserPackage?has_content]
    package ${grammar.parserPackage};
[/#if]
import java.util.*;
import java.util.function.ToIntBiFunction;

class ${grammar.nfaDataClassName} implements ${grammar.constantsClassName} {

 [#if multipleLexicalStates]
  // A lookup of the NFA function tables for the respective lexical states.
  private static final EnumMap<LexicalState,ToIntBiFunction<Integer,BitSet>[]> functionTableMap = new EnumMap<>(LexicalState.class);
 [#else]
  // We don't need the above lookup if there is only one lexical state.
   static private ToIntBiFunction<Integer, BitSet>[] nfaFunctions;
 [/#if]


  // This data holder class is never instantiated
  private ${grammar.nfaDataClassName}() {}

  /**
   * @param the lexical state
   * @return the table of function pointers that implement the lexical state
   */
  static final ToIntBiFunction<Integer,BitSet>[] getFunctionTableMap(LexicalState lexicalState) {
    [#if multipleLexicalStates]
      return functionTableMap.get(lexicalState);
    [#else]
     // We only have one lexical state in this case, so we return that!
      return nfaFunctions;
    [/#if]
  }
 
  // Initialize the various NFA method tables
  static {
    [#list grammar.lexerData.lexicalStates as lexicalState]
      NFA_FUNCTIONS_${lexicalState.name}_init();
    [/#list]
  }

 [#list grammar.lexerData.lexicalStates as lexicalState]
   [@GenerateStateCode lexicalState/]
 [/#list]  
}

[#--
  Generate all the NFA transition code
  for the given lexical state
--]
[#macro GenerateStateCode lexicalState]
  [#list lexicalState.allStates as nfaState]
    [#if nfaState.moveCodeNeeded]
      [#if nfaState.moveRanges.size() >= NFA_RANGE_THRESHOLD]
        [@GenerateMoveArray nfaState/]
      [/#if]
      [@GenerateNfaStateMethod nfaState/]
    [/#if]
  [/#list]

  static private void NFA_FUNCTIONS_${lexicalState.name}_init() {
    @SuppressWarnings("unchecked") 
    ToIntBiFunction<Integer,BitSet>[] functions = new ToIntBiFunction[${lexicalState.allStates.size()}];
    [#list lexicalState.allStates as state]
      [#if state.moveCodeNeeded]
          functions[${state.index}] = ${grammar.nfaDataClassName}::${state.methodName};
      [/#if]
    [/#list]
    [#if multipleLexicalStates]
      functionTableMap.put(LexicalState.${lexicalState.name}, functions);
    [#else]
      nfaFunctions = functions;
    [/#if]
  }
[/#macro]

[#--
   Generate the array representing the characters
   that this NfaState "accepts".
   This corresponds to the moveRanges field in 
   com.javacc.lexgen.NfaState
--]
[#macro GenerateMoveArray nfaState]
  [#var moveRanges = nfaState.moveRanges]
  [#var arrayName = nfaState.movesArrayName]
    static private int[] ${arrayName} = ${arrayName}_init();

    static private int[] ${arrayName}_init() {
        int[] result = new int[${nfaState.moveRanges.size()}];
        [#list nfaState.moveRanges as char]
          result[${char_index}] = ${grammar.utils.displayChar(char)};
        [/#list]
        return result;
    }
[/#macro] 

[#--
   Generate the method that represents the transition
   (or transitions if this is a CompositeStateSet)
   that correspond to an instanceof com.javacc.lexgen.NfaState
--]
[#macro GenerateNfaStateMethod nfaState]  
  [#if !nfaState.composite]
    static int ${nfaState.methodName}(int ch, BitSet nextStates) {
      [#if nfaState.moveRanges?size >= NFA_RANGE_THRESHOLD]
        int temp;
      [/#if]
      [@GenerateStateMove nfaState false /]
      return 0x7FFFFFFF;
    }
  [#else]
    static int ${nfaState.methodName}(int ch, BitSet nextStates) {
      int kind = 0x7FFFFFFF, temp;
    [#var states = nfaState.orderedStates]
    [#list states as state]
      [#var jumpOut = state_has_next && state.isNonOverlapping(states.subList(state_index+1, states?size))]
      [@GenerateStateMove state true jumpOut /]
      [#if state_has_next && states[state_index+1].isNonOverlapping(states.subList(0, state_index+1))]
         else
      [/#if]
    [/#list]
      return kind;
    }
  [/#if]
[/#macro]

[#--
  Generates the code for an NFA state transition
  This is a bit messy. It takes the parameters:
  inComposite means that this state move is part of
  a CompositeStateSet. In that case, we use the jumpOut
  parameter to decide whether we can just jump out of the 
  method. (This is based on whether any of the moveRanges
  for later states overlap. If not, we can jump out. This 
  is only relevant if we are in a composite state, of course.)  
  TODO: Clean this up a bit. It's a bit messy and maybe a 
  redundant as well.
--]
[#macro GenerateStateMove nfaState inComposite jumpOut]
   [#var nextState = nfaState.nextState.canonicalState]
   [#--var kindToPrint=(nfaState.nextState.type.ordinal)!MAX_INT--]
   [#var kindToPrint = nfaState.nextState.ordinal]
    if ([@NfaStateCondition nfaState/]) {
   [#if nextState.composite]
         nextStates.set(${nextState.index});
   [#else]
     [#list (nextState.epsilonMoves)! as epsilonMove]
          nextStates.set(${epsilonMove.index});
     [/#list]
   [/#if]
   [#if !inComposite]
     [#if kindToPrint != MAX_INT]
      // ${grammar.lexerData.getTokenName(kindToPrint)}
      return ${kindToPrint};
     [/#if]
   [#else]
      [#if kindToPrint != MAX_INT]
          kind = Math.min(kind, ${kindToPrint});
      [/#if]
      [#if jumpOut]
          return kind;
      [/#if]
   [/#if]
   }
[/#macro]

[#--
Generate the condition part of the NFA state transition
If the size of the moveRanges vector is greater than NFA_RANGE_THRESHOLD
it uses the canned binary search routine. For the smaller moveRanges
it just generates the inline conditional expression
--]
[#macro NfaStateCondition nfaState]
    [#var moveRanges = nfaState.moveRanges]
    [#if moveRanges?size < NFA_RANGE_THRESHOLD]
      [@RangesCondition nfaState.moveRanges /]
    [#else]
      (temp = Arrays.binarySearch(${nfaState.movesArrayName}, ch)) >=0 || temp%2 ==0
    [/#if]
[/#macro]

[#-- 
This is a recursive macro that generates the code corresponding
to the accepting condition for an NFA state. It is used
if NFA state's moveRanges array is smaller than NFA_RANGE_THRESHOLD
(which is set to 16 for now)
--]
[#macro RangesCondition moveRanges]
    [#var left = moveRanges[0], right = moveRanges[1]]
    [#var displayLeft = grammar.utils.displayChar(left), displayRight = grammar.utils.displayChar(right)]
    [#var singleChar = left == right]
    [#if moveRanges?size==2]
       [#if singleChar]
          ch == ${displayLeft}
       [#elseif left +1 == right]
          ch == ${displayLeft} || ch == ${displayRight}
       [#elseif left > 0]
          ch >= ${displayLeft} 
          [#if right < 1114111]
             && ch <= ${displayRight}
          [/#if]
       [#else]
           ch <= ${displayRight}
       [/#if]
    [#else]
       ch 
       [#if singleChar]==[#else]>=[/#if]
       ${displayLeft} 
       [#if !singleChar]
       && (ch <= ${displayRight} || ([@RangesCondition moveRanges[2..moveRanges?size-1]/]))
       [#else]
       || ([@RangesCondition moveRanges[2..moveRanges?size-1]/])
       [/#if]
    [/#if]
[/#macro]
